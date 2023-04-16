defmodule AshPostgres.Expr do
  @moduledoc false

  alias Ash.Filter
  alias Ash.Query.{BooleanExpression, Exists, Not, Ref}
  alias Ash.Query.Operator.IsNil

  alias Ash.Query.Function.{
    Ago,
    Contains,
    DateAdd,
    DateTimeAdd,
    FromNow,
    GetPath,
    If,
    Length,
    Now,
    StringJoin,
    Today,
    Type
  }

  alias AshPostgres.Functions.{Fragment, ILike, Like, TrigramSimilarity}

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
    new_expression = do_dynamic_expr(query, expression, bindings, embedded?, :boolean)
    Ecto.Query.dynamic(not (^new_expression))
  end

  defp do_dynamic_expr(
         query,
         %TrigramSimilarity{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arg1 = do_dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string)
    arg2 = do_dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string)

    Ecto.Query.dynamic(fragment("similarity(?, ?)", ^arg1, ^arg2))
  end

  defp do_dynamic_expr(
         query,
         %Like{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arg1 = do_dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string)
    arg2 = do_dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string)

    Ecto.Query.dynamic(like(^arg1, ^arg2))
  end

  defp do_dynamic_expr(
         query,
         %ILike{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    arg1 = do_dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string)
    arg2 = do_dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string)

    Ecto.Query.dynamic(ilike(^arg1, ^arg2))
    |> maybe_type(type, query)
  end

  defp do_dynamic_expr(
         query,
         %IsNil{left: left, right: right, embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    left_expr = do_dynamic_expr(query, left, bindings, pred_embedded? || embedded?)
    right_expr = do_dynamic_expr(query, right, bindings, pred_embedded? || embedded?, :boolean)
    Ecto.Query.dynamic(is_nil(^left_expr) == ^right_expr)
  end

  defp do_dynamic_expr(
         query,
         %Ago{arguments: [left, right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       )
       when is_binary(right) or is_atom(right) do
    left = do_dynamic_expr(query, left, bindings, pred_embedded? || embedded?, :integer)

    Ecto.Query.dynamic(
      fragment("(?)", datetime_add(^DateTime.utc_now(), ^left * -1, ^to_string(right)))
    )
  end

  defp do_dynamic_expr(
         query,
         %FromNow{arguments: [left, right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       )
       when is_binary(right) or is_atom(right) do
    left = do_dynamic_expr(query, left, bindings, pred_embedded? || embedded?, :integer)

    Ecto.Query.dynamic(
      fragment("(?)", datetime_add(^DateTime.utc_now(), ^left, ^to_string(right)))
    )
  end

  defp do_dynamic_expr(
         query,
         %DateTimeAdd{arguments: [datetime, amount, interval], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       )
       when is_binary(interval) or is_atom(interval) do
    datetime = do_dynamic_expr(query, datetime, bindings, pred_embedded? || embedded?)
    amount = do_dynamic_expr(query, amount, bindings, pred_embedded? || embedded?, :integer)
    Ecto.Query.dynamic(fragment("(?)", datetime_add(^datetime, ^amount, ^to_string(interval))))
  end

  defp do_dynamic_expr(
         query,
         %DateAdd{arguments: [date, amount, interval], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       )
       when is_binary(interval) or is_atom(interval) do
    date = do_dynamic_expr(query, date, bindings, pred_embedded? || embedded?)
    amount = do_dynamic_expr(query, amount, bindings, pred_embedded? || embedded?, :integer)
    Ecto.Query.dynamic(fragment("(?)", datetime_add(^date, ^amount, ^to_string(interval))))
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
    if "citext" in AshPostgres.DataLayer.Info.repo(query.__ash_bindings__.resource).installed_extensions() do
      do_dynamic_expr(
        query,
        %Fragment{
          embedded?: pred_embedded?,
          arguments: [
            raw: "(strpos((",
            expr: left,
            raw: "::citext), (",
            expr: right,
            raw: ")) > 0)"
          ]
        },
        bindings,
        embedded?,
        type
      )
    else
      do_dynamic_expr(
        query,
        %Fragment{
          embedded?: pred_embedded?,
          arguments: [
            raw: "(strpos(lower(",
            expr: left,
            raw: "), lower(",
            expr: right,
            raw: ")) > 0)"
          ]
        },
        bindings,
        embedded?,
        type
      )
    end
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
          raw: "(strpos((",
          expr: left,
          raw: "), (",
          expr: right,
          raw: ")) > 0)"
        ]
      },
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %Length{arguments: [list], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "array_length((",
          expr: list,
          raw: "), 1)"
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
      do_dynamic_expr(query, condition, bindings, pred_embedded? || embedded?)
      |> maybe_type(query, condition, condition_type)

    when_true =
      do_dynamic_expr(query, when_true, bindings, pred_embedded? || embedded?)
      |> maybe_type(query, when_true, when_true_type)

    when_false =
      do_dynamic_expr(
        query,
        when_false,
        bindings,
        pred_embedded? || embedded?
      )
      |> maybe_type(query, when_false, when_false_type)

    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "(CASE WHEN ",
          casted_expr: condition,
          raw: " THEN ",
          casted_expr: when_true,
          raw: " ELSE ",
          casted_expr: when_false,
          raw: " END)"
        ]
      },
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %StringJoin{arguments: [values, joiner], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments:
          Enum.reduce(values, [raw: "(concat_ws(", expr: joiner], fn value, acc ->
            acc ++ [raw: ", ", expr: value]
          end) ++ [raw: "))"]
      },
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %StringJoin{arguments: [values], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      query,
      %Fragment{
        embedded?: pred_embedded?,
        arguments:
          [raw: "(concat("] ++
            (values
             |> Enum.reduce([], fn value, acc ->
               acc ++ [expr: value]
             end)
             |> Enum.intersperse({:raw, ", "})) ++
            [raw: "))"]
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
          {params, [{:raw, str} | fragment_data], count}

        {:casted_expr, dynamic}, {params, fragment_data, count} ->
          {[{dynamic, :any} | params], [{:expr, {:^, [], [count]}} | fragment_data], count + 1}

        {:expr, expr}, {params, fragment_data, count} ->
          dynamic = do_dynamic_expr(query, expr, bindings, pred_embedded? || embedded?)

          {[{dynamic, :any} | params], [{:expr, {:^, [], [count]}} | fragment_data], count + 1}
      end)

    %Ecto.Query.DynamicExpr{
      fun: fn _query ->
        {{:fragment, [], Enum.reverse(fragment_data)}, Enum.reverse(params), [], %{}}
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
    left_expr = do_dynamic_expr(query, left, bindings, embedded?, :boolean)
    right_expr = do_dynamic_expr(query, right, bindings, embedded?, :boolean)

    case op do
      :and ->
        Ecto.Query.dynamic(^left_expr and ^right_expr)

      :or ->
        Ecto.Query.dynamic(^left_expr or ^right_expr)
    end
  end

  # Honestly we need to either 1. not type cast or 2. build in type compatibility concepts
  # instead of `:same` we need an `ANY COMPATIBLE` equivalent.
  @cast_operands_for [:<>]

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

    left_expr = do_dynamic_expr(query, left, bindings, pred_embedded? || embedded?, left_type)

    left_expr =
      if left_type && operator in @cast_operands_for do
        Ecto.Query.dynamic(type(^left_expr, ^left_type))
      else
        left_expr
      end

    right_expr = do_dynamic_expr(query, right, bindings, pred_embedded? || embedded?, right_type)

    right_expr =
      if right_type && operator in @cast_operands_for do
        Ecto.Query.dynamic(type(^right_expr, ^right_type))
      else
        right_expr
      end

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
        Ecto.Query.dynamic(type(^left_expr, :decimal) / type(^right_expr, :decimal))

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
              raw: "ash_elixir_and(",
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

  defp do_dynamic_expr(
         query,
         %Ash.CiString{string: string} = expression,
         bindings,
         embedded?,
         type
       ) do
    string = do_dynamic_expr(query, string, bindings, embedded?)

    require_extension!(query, "citext", expression)

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
         } = type_expr,
         bindings,
         embedded?,
         _type
       ) do
    calculation = %{calculation | load: calculation.name}

    type =
      AshPostgres.Types.parameterized_type(
        calculation.type,
        Map.get(calculation, :constraints, [])
      )

    validate_type!(query, type, type_expr)

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

        if type do
          Ecto.Query.dynamic(type(^expr, ^type))
        else
          expr
        end

      {:error, error} ->
        raise """
        Failed to hydrate references in #{inspect(calculation.module.expression(calculation.opts, calculation.context))}

        #{inspect(error)}
        """
    end
  end

  defp do_dynamic_expr(
         query,
         %Ref{
           attribute: %Ash.Resource.Calculation{calculation: {module, opts}} = calculation
         } = ref,
         bindings,
         embedded?,
         type
       ) do
    calc_type =
      AshPostgres.Types.parameterized_type(
        calculation.type,
        Map.get(calculation, :constraints, [])
      )

    validate_type!(query, calc_type, ref)

    {:ok, query_calc} =
      Ash.Query.Calculation.new(
        calculation.name,
        module,
        opts,
        calculation.type
      )

    expr = do_dynamic_expr(query, %{ref | attribute: query_calc}, bindings, embedded?, type)

    if calc_type do
      Ecto.Query.dynamic(type(^expr, ^calc_type))
    else
      expr
    end
  end

  defp do_dynamic_expr(
         query,
         %Ref{attribute: %Ash.Query.Aggregate{} = aggregate} = ref,
         bindings,
         _embedded?,
         _type
       ) do
    related = Ash.Resource.Info.related(query.__ash_bindings__.resource, ref.relationship_path)

    first_optimized_aggregate? =
      aggregate.kind == :first &&
        AshPostgres.Aggregate.single_path?(related, aggregate.relationship_path)

    {ref_binding, field_name} =
      if first_optimized_aggregate? do
        ref = %{ref | relationship_path: ref.relationship_path ++ aggregate.relationship_path}
        ref_binding = ref_binding(ref, bindings)

        if is_nil(ref_binding) do
          raise "Error while building reference: #{inspect(ref)}"
        end

        {ref_binding, aggregate.field}
      else
        ref_binding = ref_binding(ref, bindings)

        if is_nil(ref_binding) do
          raise "Error while building reference: #{inspect(ref)}"
        end

        {ref_binding, aggregate.name}
      end

    ref_binding =
      if ref.relationship_path == [] || first_optimized_aggregate? do
        ref_binding
      else
        ref_binding + 1
      end

    expr =
      if query.__ash_bindings__[:parent?] do
        Ecto.Query.dynamic(field(parent_as(^ref_binding), ^field_name))
      else
        Ecto.Query.dynamic(field(as(^ref_binding), ^field_name))
      end

    type = AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)
    validate_type!(query, type, ref)

    type =
      if type && aggregate.kind == :list do
        {:array, type}
      else
        type
      end

    coalesced =
      if is_nil(aggregate.default_value) do
        expr
      else
        if type do
          Ecto.Query.dynamic(coalesce(^expr, type(^aggregate.default_value, ^type)))
        else
          Ecto.Query.dynamic(coalesce(^expr, ^aggregate.default_value))
        end
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

    type =
      AshPostgres.Types.parameterized_type(
        calculation.type,
        Map.get(calculation, :constraints, [])
      )

    validate_type!(query, type, ref)

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

        if type do
          Ecto.Query.dynamic(type(^expr, ^type))
        else
          expr
        end

      _ ->
        raise "Failed to hydrate references in #{inspect(calculation.module.expression(calculation.opts, calculation.context))}"
    end
  end

  defp do_dynamic_expr(
         query,
         %Type{arguments: [arg1, arg2, constraints]},
         bindings,
         embedded?,
         _type
       ) do
    arg2 = Ash.Type.get_type(arg2)
    arg1 = maybe_uuid_to_binary(arg2, arg1, arg1)
    type = AshPostgres.Types.parameterized_type(arg2, constraints)

    Ecto.Query.dynamic(type(^do_dynamic_expr(query, arg1, bindings, embedded?, type), ^type))
  end

  defp do_dynamic_expr(
         query,
         %Now{embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      query,
      DateTime.utc_now(),
      bindings,
      embedded? || pred_embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %Today{embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      query,
      Date.utc_today(),
      bindings,
      embedded? || pred_embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %Ash.Query.Parent{expr: expr},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      %{
        query
        | __ash_bindings__: Map.put(query.__ash_bindings__.parent_bindings, :parent?, true)
      },
      expr,
      bindings,
      embedded?,
      type
    )
  end

  defp do_dynamic_expr(
         query,
         %Exists{at_path: at_path, path: [first | rest], expr: expr},
         bindings,
         _embedded?,
         _type
       ) do
    resource = Ash.Resource.Info.related(query.__ash_bindings__.resource, at_path)
    first_relationship = Ash.Resource.Info.relationship(resource, first)

    last_relationship =
      Enum.reduce(rest, first_relationship, fn name, relationship ->
        Ash.Resource.Info.relationship(relationship.destination, name)
      end)

    {:ok, expr} =
      Ash.Filter.hydrate_refs(expr, %{
        resource: last_relationship.destination,
        aggregates: %{},
        parent_stack: [
          query.__ash_bindings__.resource
          | query.__ash_bindings__[:parent_resources] || []
        ],
        calculations: %{},
        public?: false
      })

    filter =
      %Ash.Filter{expression: expr, resource: first_relationship.destination}
      |> nest_expression(rest)

    {:ok, source} =
      AshPostgres.Join.maybe_get_resource_query(
        first_relationship.destination,
        first_relationship,
        query
      )

    source_ref =
      ref_binding(
        %Ref{
          attribute: Ash.Resource.Info.attribute(resource, first_relationship.source_attribute),
          relationship_path: at_path,
          resource: resource
        },
        bindings
      )

    used_calculations =
      Ash.Filter.used_calculations(
        filter,
        first_relationship.destination,
        []
      )

    used_aggregates =
      filter
      |> AshPostgres.Aggregate.used_aggregates(
        first_relationship.destination,
        used_calculations,
        []
      )
      |> Enum.map(fn aggregate ->
        %{aggregate | load: aggregate.name}
      end)

    {:ok, filtered} =
      source
      |> set_parent_path(query)
      |> AshPostgres.Aggregate.add_aggregates(
        used_aggregates,
        first_relationship.destination,
        false
      )
      |> case do
        {:ok, query} ->
          AshPostgres.DataLayer.filter(
            query,
            filter,
            first_relationship.destination,
            no_this?: true
          )

        {:error, error} ->
          {:error, error}
      end

    free_binding = filtered.__ash_bindings__.current

    exists_query =
      if first_relationship.type == :many_to_many do
        through_relationship =
          Ash.Resource.Info.relationship(resource, first_relationship.join_relationship)

        through_bindings =
          query
          |> Map.delete(:__ash_bindings__)
          |> AshPostgres.DataLayer.default_bindings(
            query.__ash_bindings__.resource,
            query.__ash_bindings__.context
          )
          |> Map.get(:__ash_bindings__)
          |> Map.put(:bindings, %{
            free_binding => %{path: [], source: first_relationship.through, type: :left}
          })

        {:ok, through} =
          AshPostgres.Join.maybe_get_resource_query(
            first_relationship.through,
            through_relationship,
            query,
            [],
            through_bindings
          )

        Ecto.Query.from(destination in filtered,
          join: through in ^through,
          as: ^free_binding,
          on:
            field(through, ^first_relationship.destination_attribute_on_join_resource) ==
              field(destination, ^first_relationship.destination_attribute),
          on:
            field(parent_as(^source_ref), ^first_relationship.source_attribute) ==
              field(through, ^first_relationship.source_attribute_on_join_resource)
        )
      else
        Ecto.Query.from(destination in filtered,
          where:
            field(parent_as(^source_ref), ^first_relationship.source_attribute) ==
              field(destination, ^first_relationship.destination_attribute)
        )
      end

    exists_query =
      exists_query
      |> Ecto.Query.exclude(:select)
      |> Ecto.Query.select(1)
      |> AshPostgres.DataLayer.set_subquery_prefix(query, first_relationship.destination)

    Ecto.Query.dynamic(exists(Ecto.Query.subquery(exists_query)))
  end

  defp do_dynamic_expr(
         query,
         %Ref{attribute: %Ash.Resource.Attribute{name: name, type: attr_type}} = ref,
         bindings,
         _embedded?,
         expr_type
       ) do
    ref_binding = ref_binding(ref, bindings)

    if is_nil(ref_binding) do
      raise "Error while building reference: #{inspect(ref)}"
    end

    case AshPostgres.Types.parameterized_type(attr_type || expr_type, []) do
      nil ->
        if query.__ash_bindings__[:parent?] do
          Ecto.Query.dynamic(field(parent_as(^ref_binding), ^name))
        else
          Ecto.Query.dynamic(field(as(^ref_binding), ^name))
        end

      type ->
        validate_type!(query, type, ref)

        if query.__ash_bindings__[:parent?] do
          Ecto.Query.dynamic(type(field(parent_as(^ref_binding), ^name), ^type))
        else
          Ecto.Query.dynamic(type(field(as(^ref_binding), ^name), ^type))
        end
    end
  end

  defp do_dynamic_expr(query, other, bindings, true, type) do
    if other && is_atom(other) && !is_boolean(other) do
      to_string(other)
    else
      if Ash.Filter.TemplateHelpers.expr?(other) do
        if is_list(other) do
          list_expr(query, other, bindings, true, type)
        else
          raise "Unsupported expression in AshPostgres query: #{inspect(other)}"
        end
      else
        maybe_sanitize_list(query, other, bindings, true, type)
      end
    end
  end

  defp do_dynamic_expr(query, value, bindings, embedded?, {:in, type}) when is_list(value) do
    list_expr(query, value, bindings, embedded?, {:array, type})
  end

  defp do_dynamic_expr(query, value, bindings, embedded?, type)
       when not is_nil(value) and is_atom(value) and not is_boolean(value) do
    do_dynamic_expr(query, to_string(value), bindings, embedded?, type)
  end

  defp do_dynamic_expr(query, value, bindings, false, type) when type == nil or type == :any do
    if is_list(value) do
      list_expr(query, value, bindings, false, type)
    else
      maybe_sanitize_list(query, value, bindings, true, type)
    end
  end

  defp do_dynamic_expr(query, value, bindings, false, type) do
    if Ash.Filter.TemplateHelpers.expr?(value) do
      if is_list(value) do
        list_expr(query, value, bindings, false, type)
      else
        raise "Unsupported expression in AshPostgres query: #{inspect(value)}"
      end
    else
      case maybe_sanitize_list(query, value, bindings, true, type) do
        ^value ->
          type = AshPostgres.Types.parameterized_type(type, [])
          validate_type!(query, type, value)

          Ecto.Query.dynamic(type(^value, ^type))

        value ->
          value
      end
    end
  end

  defp list_expr(query, value, bindings, embedded?, type) do
    type =
      case type do
        {:array, type} -> type
        {:in, type} -> type
        _ -> nil
      end

    {params, exprs, _} =
      Enum.reduce(value, {[], [], 0}, fn value, {params, data, count} ->
        case do_dynamic_expr(query, value, bindings, embedded?, type) do
          %Ecto.Query.DynamicExpr{} = dynamic ->
            result =
              Ecto.Query.Builder.Dynamic.partially_expand(
                :select,
                query,
                dynamic,
                params,
                count
              )

            expr = elem(result, 0)
            new_params = elem(result, 1)
            new_count = result |> Tuple.to_list() |> List.last()

            {new_params, [expr | data], new_count}

          other ->
            {params, [other | data], count}
        end
      end)

    exprs = Enum.reverse(exprs)

    %Ecto.Query.DynamicExpr{
      fun: fn _query ->
        {exprs, Enum.reverse(params), [], []}
      end,
      binding: [],
      file: __ENV__.file,
      line: __ENV__.line
    }
  end

  defp maybe_uuid_to_binary({:array, type}, value, _original_value) when is_list(value) do
    Enum.map(value, &maybe_uuid_to_binary(type, &1, &1))
  end

  defp maybe_uuid_to_binary(type, value, original_value)
       when type in [
              Ash.Type.UUID.EctoType,
              :uuid
            ] and is_binary(value) do
    case Ecto.UUID.dump(value) do
      {:ok, encoded} -> encoded
      _ -> original_value
    end
  end

  defp maybe_uuid_to_binary(_type, _value, original_value), do: original_value

  defp maybe_type(dynamic, _query, _type_expr, nil), do: dynamic

  defp maybe_type(dynamic, query, type_expr, type) do
    type =
      AshPostgres.Types.parameterized_type(
        type,
        []
      )

    if type do
      validate_type!(query, type, type_expr)
      Ecto.Query.dynamic(type(^dynamic, ^type))
    else
      dynamic
    end
  end

  defp validate_type!(query, type, context) do
    case type do
      {:parameterized, Ash.Type.CiStringWrapper.EctoType, _} ->
        require_extension!(query, "citext", context)

      :ci_string ->
        require_extension!(query, "citext", context)

      :citext ->
        require_extension!(query, "citext", context)

      _ ->
        :ok
    end
  end

  defp maybe_type(dynamic, nil, _query), do: dynamic

  defp maybe_type(dynamic, type, query) do
    type = AshPostgres.Types.parameterized_type(type, [])
    validate_type!(query, type, type)

    Ecto.Query.dynamic(type(^dynamic, ^type))
  end

  defp maybe_sanitize_list(query, value, bindings, embedded?, type) do
    if is_list(value) do
      Enum.map(value, &do_dynamic_expr(query, &1, bindings, embedded?, type))
    else
      value
    end
  end

  defp ref_binding(
         %{attribute: %Ash.Query.Aggregate{name: name}, relationship_path: []},
         bindings
       ) do
    Enum.find_value(bindings.bindings, fn {binding, data} ->
      data.type == :aggregate &&
        Enum.any?(data.aggregates, &(&1.name == name)) && binding
    end)
  end

  defp ref_binding(%{attribute: %Ash.Resource.Attribute{}} = ref, bindings) do
    Enum.find_value(bindings.bindings, fn {binding, data} ->
      data.path == ref.relationship_path && data.type in [:inner, :left, :root] && binding
    end)
  end

  defp ref_binding(%{attribute: %Ash.Query.Aggregate{}} = ref, bindings) do
    Enum.find_value(bindings.bindings, fn {binding, data} ->
      data.path == ref.relationship_path && data.type in [:inner, :left, :root] && binding
    end)
  end

  defp do_get_path(
         query,
         %GetPath{arguments: [left, right], embedded?: pred_embedded?} = get_path,
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
      type =
        AshPostgres.Types.parameterized_type(
          type,
          []
        )

      validate_type!(query, type, get_path)

      Ecto.Query.dynamic(type(^expr, ^type))
    else
      expr
    end
  end

  defp require_ash_functions!(query) do
    installed_extensions =
      AshPostgres.DataLayer.Info.repo(query.__ash_bindings__.resource).installed_extensions()

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

  defp require_extension!(query, extension, context) do
    repo = AshPostgres.DataLayer.Info.repo(query.__ash_bindings__.resource)

    unless extension in repo.installed_extensions() do
      raise Ash.Error.Query.InvalidExpression,
        expression: context,
        message:
          "The #{extension} extension needs to be installed before #{inspect(context)} can be used. Please add \"#{extension}\" to the list of installed_extensions in #{inspect(repo)}."
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

  defp set_parent_path(query, parent) do
    # This is a stupid name. Its actually the path we *remove* when stepping up a level. I.e the child's path
    Map.update!(query, :__ash_bindings__, fn ash_bindings ->
      ash_bindings
      |> Map.put(:parent_bindings, parent.__ash_bindings__)
      |> Map.put(:parent_resources, [
        parent.__ash_bindings__.resource | parent.__ash_bindings__[:parent_resources] || []
      ])
    end)
  end

  defp nest_expression(expression, relationship_path) do
    case expression do
      {key, value} when is_atom(key) ->
        {key, nest_expression(value, relationship_path)}

      %Not{expression: expression} = not_expr ->
        %{not_expr | expression: nest_expression(expression, relationship_path)}

      %BooleanExpression{left: left, right: right} = expression ->
        %{
          expression
          | left: nest_expression(left, relationship_path),
            right: nest_expression(right, relationship_path)
        }

      %{__operator__?: true, left: left, right: right} = op ->
        left = nest_expression(left, relationship_path)
        right = nest_expression(right, relationship_path)
        %{op | left: left, right: right}

      %Ref{} = ref ->
        add_to_ref_path(ref, relationship_path)

      %{__function__?: true, arguments: args} = func ->
        %{func | arguments: Enum.map(args, &nest_expression(&1, relationship_path))}

      %Ash.Query.Exists{} = exists ->
        %{exists | at_path: relationship_path ++ exists.at_path}

      %Ash.Query.Parent{} = parent ->
        parent

      %Ash.Query.Call{args: args} = call ->
        %{call | args: Enum.map(args, &nest_expression(&1, relationship_path))}

      %Ash.Filter{expression: expression} = filter ->
        %{filter | expression: nest_expression(expression, relationship_path)}

      other ->
        other
    end
  end

  defp add_to_ref_path(%Ref{relationship_path: relationship_path} = ref, to_add) do
    %{ref | relationship_path: to_add ++ relationship_path}
  end
end
