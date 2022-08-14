defmodule AshPostgres.Expr do
  @moduledoc false

  alias Ash.Filter
  alias Ash.Query.{BooleanExpression, Not, Ref}
  alias Ash.Query.Operator.IsNil
  alias Ash.Query.Function.{Ago, Contains, GetPath, If}
  alias AshPostgres.Functions.{Fragment, TrigramSimilarity, Type}

  require Ecto.Query

  def dynamic_expr(query, expr, bindings, embedded? \\ false, type \\ nil)

  def dynamic_expr(query, %Filter{expression: expression}, bindings, embedded?, type) do
    dynamic_expr(query, expression, bindings, embedded?, type)
  end

  # A nil filter means "everything"
  def dynamic_expr(_, nil, _, _, _), do: true
  # A true filter means "everything"
  def dynamic_expr(_, true, _, _, _), do: true
  # A false filter means "nothing"
  def dynamic_expr(_, false, _, _, _), do: false

  def dynamic_expr(query, expression, bindings, embedded?, type) do
    do_dynamic_expr(query, expression, bindings, embedded?, type)
  end

  defp do_dynamic_expr(query, expr, bindings, embedded?, type \\ nil)

  defp do_dynamic_expr(_, {:embed, other}, _bindings, _true, _type) do
    other
  end

  defp do_dynamic_expr(query, %Not{expression: expression}, bindings, embedded?, _type) do
    new_expression = do_dynamic_expr(query, expression, bindings, embedded?)
    Ecto.Query.dynamic(not (^new_expression))
  end

  defp do_dynamic_expr(
         query,
         %TrigramSimilarity{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    arg1 = do_dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?)
    arg2 = do_dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?)

    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "similarity(",
          expr: arg1,
          raw: ", ",
          expr: arg2,
          raw: ")"
        ]
      },
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %IsNil{left: left, right: right, embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    left_expr = do_dynamic_expr(query, left, bindings, pred_embedded? || embedded?)
    right_expr = do_dynamic_expr(query, right, bindings, pred_embedded? || embedded?)
    Ecto.Query.dynamic(is_nil(^left_expr) == ^right_expr)
  end

  defp do_dynamic_expr(
         _query,
         %Ago{arguments: [left, right], embedded?: _pred_embedded?},
         _bindings,
         _embedded?,
         _type
       )
       when is_integer(left) and (is_binary(right) or is_atom(right)) do
    Ecto.Query.dynamic(datetime_add(^DateTime.utc_now(), ^left * -1, ^to_string(right)))
  end

  defp do_dynamic_expr(
         query,
         %GetPath{
           arguments: [%Ref{attribute: %{type: type}}, right]
         } = get_path,
         bindings,
         embedded?,
         nil
       )
       when is_atom(type) and is_list(right) do
    if Ash.Type.embedded_type?(type) do
      type = determine_type_at_path(type, right)
      do_get_path(query, get_path, bindings, embedded?, type)
    else
      do_get_path(query, get_path, bindings, embedded?)
    end
  end

  defp do_dynamic_expr(
         query,
         %GetPath{
           arguments: [%Ref{attribute: %{type: {:array, type}}}, right]
         } = get_path,
         bindings,
         embedded?,
         nil
       )
       when is_atom(type) and is_list(right) do
    if Ash.Type.embedded_type?(type) do
      type = determine_type_at_path(type, right)
      do_get_path(query, get_path, bindings, embedded?, type)
    else
      do_get_path(query, get_path, bindings, embedded?)
    end
  end

  defp do_dynamic_expr(
         query,
         %GetPath{} = get_path,
         bindings,
         embedded?,
         type
       ) do
    do_get_path(query, get_path, bindings, embedded?, type)
  end

  defp do_dynamic_expr(
         query,
         %Contains{arguments: [left, %Ash.CiString{} = right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "strpos(",
          expr: left,
          raw: "::citext, ",
          expr: right,
          raw: ") > 0"
        ]
      },
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %Contains{arguments: [left, right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "strpos((",
          expr: left,
          raw: "), ",
          expr: right,
          raw: ") > 0"
        ]
      },
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %If{arguments: [condition, when_true, when_false], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    [condition_type, when_true_type, when_false_type] =
      case AshPostgres.Types.determine_types(If, [condition, when_true, when_false]) do
        [condition_type, when_true] ->
          [condition_type, when_true, nil]

        [condition_type, when_true, when_false] ->
          [condition_type, when_true, when_false]
      end
      |> Enum.map(fn type ->
        if type == :any || type == {:in, :any} do
          nil
        else
          type
        end
      end)
      |> case do
        [condition_type, nil, nil] ->
          [condition_type, type, type]

        [condition_type, when_true, nil] ->
          [condition_type, when_true, type]

        [condition_type, nil, when_false] ->
          [condition_type, type, when_false]

        [condition_type, when_true, when_false] ->
          [condition_type, when_true, when_false]
      end

    condition =
      do_dynamic_expr(query, condition, bindings, pred_embedded? || embedded?, condition_type)

    when_true =
      do_dynamic_expr(query, when_true, bindings, pred_embedded? || embedded?, when_true_type)

    when_false =
      do_dynamic_expr(
        query,
        when_false,
        bindings,
        pred_embedded? || embedded?,
        when_false_type
      )

    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "CASE WHEN ",
          casted_expr: condition,
          raw: " THEN ",
          casted_expr: when_true,
          raw: " ELSE ",
          casted_expr: when_false,
          raw: " END"
        ]
      },
      bindings,
      embedded?,
      type
    )
  end

  # Sorry :(
  # This is bad to do, but is the only reasonable way I could find.
  defp do_dynamic_expr(
         query,
         %Fragment{arguments: arguments, embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arguments =
      case arguments do
        [{:raw, _} | _] ->
          arguments

        arguments ->
          [{:raw, ""} | arguments]
      end

    arguments =
      case List.last(arguments) do
        nil ->
          arguments

        {:raw, _} ->
          arguments

        _ ->
          arguments ++ [{:raw, ""}]
      end

    {params, fragment_data, _} =
      Enum.reduce(arguments, {[], [], 0}, fn
        {:raw, str}, {params, fragment_data, count} ->
          {params, fragment_data ++ [{:raw, str}], count}

        {:casted_expr, dynamic}, {params, fragment_data, count} ->
          {expr, new_params, new_count} =
            Ecto.Query.Builder.Dynamic.partially_expand(
              :select,
              query,
              dynamic,
              params,
              count
            )

          {new_params, fragment_data ++ [{:expr, expr}], new_count}

        {:expr, expr}, {params, fragment_data, count} ->
          dynamic = do_dynamic_expr(query, expr, bindings, pred_embedded? || embedded?)

          {expr, new_params, new_count} =
            Ecto.Query.Builder.Dynamic.partially_expand(
              :select,
              query,
              dynamic,
              params,
              count
            )

          {new_params, fragment_data ++ [{:expr, expr}], new_count}
      end)

    %Ecto.Query.DynamicExpr{
      fun: fn _query ->
        {{:fragment, [], fragment_data}, Enum.reverse(params), []}
      end,
      binding: [],
      file: __ENV__.file,
      line: __ENV__.line
    }
  end

  defp do_dynamic_expr(
         query,
         %BooleanExpression{op: op, left: left, right: right},
         bindings,
         embedded?,
         _type
       ) do
    left_expr = do_dynamic_expr(query, left, bindings, embedded?)
    right_expr = do_dynamic_expr(query, right, bindings, embedded?)

    case op do
      :and ->
        Ecto.Query.dynamic(^left_expr and ^right_expr)

      :or ->
        Ecto.Query.dynamic(^left_expr or ^right_expr)
    end
  end

  defp do_dynamic_expr(
         query,
         %mod{
           __predicate__?: _,
           left: left,
           right: right,
           embedded?: pred_embedded?,
           operator: operator
         },
         bindings,
         embedded?,
         type
       ) do
    [left_type, right_type] =
      mod
      |> AshPostgres.Types.determine_types([left, right])
      |> Enum.map(fn type ->
        if type == :any || type == {:in, :any} do
          nil
        else
          type
        end
      end)

    left_expr = do_dynamic_expr(query, left, bindings, pred_embedded? || embedded?, left_type)

    right_expr = do_dynamic_expr(query, right, bindings, pred_embedded? || embedded?, right_type)

    case operator do
      :== ->
        Ecto.Query.dynamic(^left_expr == ^right_expr)

      :!= ->
        Ecto.Query.dynamic(^left_expr != ^right_expr)

      :> ->
        Ecto.Query.dynamic(^left_expr > ^right_expr)

      :< ->
        Ecto.Query.dynamic(^left_expr < ^right_expr)

      :>= ->
        Ecto.Query.dynamic(^left_expr >= ^right_expr)

      :<= ->
        Ecto.Query.dynamic(^left_expr <= ^right_expr)

      :in ->
        Ecto.Query.dynamic(^left_expr in ^right_expr)

      :+ ->
        Ecto.Query.dynamic(^left_expr + ^right_expr)

      :- ->
        Ecto.Query.dynamic(^left_expr - ^right_expr)

      :/ ->
        Ecto.Query.dynamic(^left_expr / ^right_expr)

      :* ->
        Ecto.Query.dynamic(^left_expr * ^right_expr)

      :<> ->
        do_dynamic_expr(
          query,
          %Fragment{
            embedded?: pred_embedded?,
            arguments: [
              raw: "(",
              casted_expr: left_expr,
              raw: " || ",
              casted_expr: right_expr,
              raw: ")"
            ]
          },
          bindings,
          embedded?,
          type
        )

      :|| ->
        require_ash_functions!(query)

        do_dynamic_expr(
          query,
          %Fragment{
            embedded?: pred_embedded?,
            arguments: [
              raw: "ash_elixir_or(",
              casted_expr: left_expr,
              raw: ", ",
              casted_expr: right_expr,
              raw: ")"
            ]
          },
          bindings,
          embedded?,
          type
        )

      :&& ->
        require_ash_functions!(query)

        do_dynamic_expr(
          query,
          %Fragment{
            embedded?: pred_embedded?,
            arguments: [
              raw: "ash_elixir_or(",
              casted_expr: left_expr,
              raw: ", ",
              casted_expr: right_expr,
              raw: ")"
            ]
          },
          bindings,
          embedded?,
          type
        )

      other ->
        raise "Operator not implemented #{other}"
    end
  end

  defp do_dynamic_expr(query, %MapSet{} = mapset, bindings, embedded?, type) do
    do_dynamic_expr(query, Enum.to_list(mapset), bindings, embedded?, type)
  end

  defp do_dynamic_expr(query, %Ash.CiString{string: string}, bindings, embedded?, type) do
    string = do_dynamic_expr(query, string, bindings, embedded?)

    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: embedded?,
        arguments: [
          raw: "",
          casted_expr: string,
          raw: "::citext"
        ]
      },
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %Ref{
           attribute: %Ash.Query.Calculation{} = calculation,
           relationship_path: [],
           resource: resource
         },
         bindings,
         embedded?,
         _type
       ) do
    calculation = %{calculation | load: calculation.name}
    type = AshPostgres.Types.parameterized_type(calculation.type, [])

    case Ash.Filter.hydrate_refs(
           calculation.module.expression(calculation.opts, calculation.context),
           %{
             resource: resource,
             aggregates: %{},
             calculations: %{},
             public?: false
           }
         ) do
      {:ok, expression} ->
        expr =
          do_dynamic_expr(
            query,
            expression,
            bindings,
            embedded?,
            type
          )

        Ecto.Query.dynamic(type(^expr, ^type))

      {:error, _error} ->
        raise "Failed to hydrate references in #{inspect(calculation.module.expression(calculation.opts, calculation.context))}"
    end
  end

  defp do_dynamic_expr(
         _query,
         %Ref{attribute: %Ash.Query.Aggregate{} = aggregate} = ref,
         bindings,
         _embedded?,
         _type
       ) do
    ref_binding = ref_binding(ref, bindings)

    if is_nil(ref_binding) do
      raise "Error while building reference: #{inspect(ref)}"
    end

    expr = Ecto.Query.dynamic(field(as(^ref_binding), ^aggregate.name))

    type = AshPostgres.Types.parameterized_type(aggregate.type, [])

    type =
      if type && aggregate.kind == :list do
        {:array, type}
      else
        type
      end

    coalesced =
      if aggregate.default_value do
        if type do
          Ecto.Query.dynamic(coalesce(^expr, type(^aggregate.default_value, ^type)))
        else
          Ecto.Query.dynamic(coalesce(^expr, ^aggregate.default_value))
        end
      else
        expr
      end

    if type do
      Ecto.Query.dynamic(type(^coalesced, ^type))
    else
      coalesced
    end
  end

  defp do_dynamic_expr(
         query,
         %Ref{
           attribute: %Ash.Query.Calculation{} = calculation,
           relationship_path: relationship_path
         } = ref,
         bindings,
         embedded?,
         _type
       ) do
    binding_to_replace =
      Enum.find_value(bindings.bindings, fn {i, binding} ->
        if binding.path == relationship_path do
          i
        end
      end)

    temp_bindings =
      bindings.bindings
      |> Map.delete(0)
      |> Map.update!(binding_to_replace, &Map.merge(&1, %{path: [], type: :root}))

    type = AshPostgres.Types.parameterized_type(calculation.type, [])

    case Ash.Filter.hydrate_refs(
           calculation.module.expression(calculation.opts, calculation.context),
           %{
             resource: ref.resource,
             aggregates: %{},
             calculations: %{},
             public?: false
           }
         ) do
      {:ok, hydrated} ->
        expr =
          do_dynamic_expr(
            query,
            Ash.Filter.update_aggregates(hydrated, fn aggregate, _ ->
              %{aggregate | relationship_path: []}
            end),
            %{bindings | bindings: temp_bindings},
            embedded?,
            type
          )

        Ecto.Query.dynamic(type(^expr, ^type))

      _ ->
        raise "Failed to hydrate references in #{inspect(calculation.module.expression(calculation.opts, calculation.context))}"
    end
  end

  defp do_dynamic_expr(
         query,
         %Type{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arg1 = do_dynamic_expr(query, arg1, bindings, false)
    arg2 = do_dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?)
    type = AshPostgres.Types.parameterized_type(arg2, [])

    if type do
      Ecto.Query.dynamic(type(^arg1, ^type))
    else
      raise "Attempted to explicitly cast to a type that has `cast_in_query?` configured to `false`, or for which a type could not be determined."
    end
  end

  defp do_dynamic_expr(
         query,
         %Type{arguments: [arg1, arg2, constraints], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arg1 = do_dynamic_expr(query, arg1, bindings, false)
    arg2 = do_dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?)
    type = AshPostgres.Types.parameterized_type(arg2, constraints)

    if type do
      Ecto.Query.dynamic(type(^arg1, ^type))
    else
      raise "Attempted to explicitly cast to a type that has `cast_in_query?` configured to `false`, or for which a type could not be determined."
    end
  end

  defp do_dynamic_expr(
         _query,
         %Ref{attribute: %Ash.Resource.Attribute{name: name}} = ref,
         bindings,
         _embedded?,
         _type
       ) do
    ref_binding = ref_binding(ref, bindings)

    if is_nil(ref_binding) do
      raise "Error while building reference: #{inspect(ref)}"
    end

    Ecto.Query.dynamic(field(as(^ref_binding), ^name))
  end

  defp do_dynamic_expr(_query, other, _bindings, true, _type) do
    if other && is_atom(other) && !is_boolean(other) do
      to_string(other)
    else
      other
    end
  end

  defp do_dynamic_expr(_query, value, _bindings, false, {:in, type}) when is_list(value) do
    value = maybe_sanitize_list(value)

    Ecto.Query.dynamic(type(^value, ^{:array, type}))
  end

  defp do_dynamic_expr(query, value, bindings, false, type)
       when not is_nil(value) and is_atom(value) and not is_boolean(value) do
    do_dynamic_expr(query, to_string(value), bindings, false, type)
  end

  defp do_dynamic_expr(_query, value, _bindings, false, type) when type == nil or type == :any do
    value = maybe_sanitize_list(value)

    Ecto.Query.dynamic(^value)
  end

  defp do_dynamic_expr(_query, value, _bindings, false, type) do
    value = maybe_sanitize_list(value)
    Ecto.Query.dynamic(type(^value, ^type))
  end

  defp maybe_sanitize_list(value) do
    if is_list(value) do
      Enum.map(value, fn value ->
        if value && is_atom(value) && !is_boolean(value) do
          to_string(value)
        else
          value
        end
      end)
    else
      value
    end
  end

  defp ref_binding(
         %{attribute: %Ash.Query.Aggregate{} = aggregate, relationship_path: []},
         bindings
       ) do
    Enum.find_value(bindings.bindings, fn {binding, data} ->
      data.path == aggregate.relationship_path && data.type == :aggregate && binding
    end) ||
      Enum.find_value(bindings.bindings, fn {binding, data} ->
        data.path == aggregate.relationship_path && data.type in [:inner, :left, :root] && binding
      end)
  end

  defp ref_binding(%{attribute: %Ash.Resource.Attribute{}} = ref, bindings) do
    Enum.find_value(bindings.bindings, fn {binding, data} ->
      data.path == ref.relationship_path && data.type in [:inner, :left, :root] && binding
    end) ||
      Enum.find_value(bindings.bindings, fn {binding, data} ->
        data.path == ref.relationship_path && data.type == :aggregate && binding
      end)
  end

  defp ref_binding(%{attribute: %Ash.Query.Aggregate{}} = ref, bindings) do
    Enum.find_value(bindings.bindings, fn {binding, data} ->
      data.path == ref.relationship_path && data.type in [:inner, :left, :root] && binding
    end)
  end

  defp do_get_path(
         query,
         %GetPath{arguments: [left, right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type \\ nil
       ) do
    path = Enum.map(right, &to_string/1)

    expr =
      do_dynamic_expr(
        query,
        %Fragment{
          embedded?: pred_embedded?,
          arguments: [
            raw: "(",
            expr: left,
            raw: " #>> ",
            expr: path,
            raw: ")"
          ]
        },
        bindings,
        embedded?,
        type
      )

    if type do
      # If we know a type here we use it, since we're pulling out text
      Ecto.Query.dynamic(type(^expr, ^type))
    else
      expr
    end
  end

  defp require_ash_functions!(query) do
    installed_extensions =
      AshPostgres.repo(query.__ash_bindings__.resource).installed_extensions()

    unless "ash-functions" in installed_extensions do
      raise """
      Cannot use `||` or `&&` operators without adding the extension `ash-functions` to your repo.

      Add it to the list in `installed_extensions/0`

      If you are using the migration generator, you will then need to generate migrations.
      If not, you will need to copy the following into a migration:

      execute(\"\"\"
      CREATE OR REPLACE FUNCTION ash_elixir_or(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE)
      AS $$ SELECT COALESCE(NULLIF($1, FALSE), $2) $$
      LANGUAGE SQL;
      \"\"\")

      execute(\"\"\"
      CREATE OR REPLACE FUNCTION ash_elixir_or(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE)
      AS $$ SELECT COALESCE($1, $2) $$
      LANGUAGE SQL;
      \"\"\")

      execute(\"\"\"
      CREATE OR REPLACE FUNCTION ash_elixir_and(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) AS $$
        SELECT CASE
          WHEN $1 IS TRUE THEN $2
          ELSE $1
        END $$
      LANGUAGE SQL;
      \"\"\")

      execute(\"\"\"
      CREATE OR REPLACE FUNCTION ash_elixir_and(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) AS $$
        SELECT CASE
          WHEN $1 IS NOT NULL THEN $2
          ELSE $1
        END $$
      LANGUAGE SQL;
      \"\"\")
      """
    end
  end

  defp determine_type_at_path(type, path) do
    path
    |> Enum.reject(&is_integer/1)
    |> do_determine_type_at_path(type)
    |> case do
      nil ->
        nil

      {type, constraints} ->
        AshPostgres.Types.parameterized_type(type, constraints)
    end
  end

  defp do_determine_type_at_path([], _), do: nil

  defp do_determine_type_at_path([item], type) do
    case Ash.Resource.Info.attribute(type, item) do
      nil ->
        nil

      %{type: {:array, type}, constraints: constraints} ->
        constraints = constraints[:items] || []

        {type, constraints}

      %{type: type, constraints: constraints} ->
        {type, constraints}
    end
  end

  defp do_determine_type_at_path([item | rest], type) do
    case Ash.Resource.Info.attribute(type, item) do
      nil ->
        nil

      %{type: {:array, type}} ->
        if Ash.Type.embedded_type?(type) do
          type
        else
          nil
        end

      %{type: type} ->
        if Ash.Type.embedded_type?(type) do
          type
        else
          nil
        end
    end
    |> case do
      nil ->
        nil

      type ->
        do_determine_type_at_path(rest, type)
    end
  end
end
