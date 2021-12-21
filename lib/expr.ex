defmodule AshPostgres.Expr do
  @moduledoc false

  alias Ash.Filter
  alias Ash.Query.{BooleanExpression, Ref, Not}
  alias Ash.Query.Operator.{IsNil}
  alias Ash.Query.Function.{Ago, Contains, If}
  alias AshPostgres.Functions.{TrigramSimilarity, Type, Fragment}

  require Ecto.Query

  def dynamic_expr(expr, bindings, embedded? \\ false, type \\ nil)

  def dynamic_expr(%Filter{expression: expression}, bindings, embedded?, type) do
    dynamic_expr(expression, bindings, embedded?, type)
  end

  # A nil filter means "everything"
  def dynamic_expr(nil, _, _, _), do: {[], true}
  # A true filter means "everything"
  def dynamic_expr(true, _, _, _), do: {[], true}
  # A false filter means "nothing"
  def dynamic_expr(false, _, _, _), do: {[], false}

  def dynamic_expr(expression, bindings, embedded?, type) do
    do_dynamic_expr(expression, bindings, embedded?, type)
  end

  defp do_dynamic_expr(expr, bindings, embedded?, type \\ nil)

  defp do_dynamic_expr({:embed, other}, _bindings, _true, _type) do
    other
  end

  defp do_dynamic_expr(%Not{expression: expression}, bindings, embedded?, _type) do
    new_expression = do_dynamic_expr(expression, bindings, embedded?)
    Ecto.Query.dynamic(not (^new_expression))
  end

  defp do_dynamic_expr(
         %TrigramSimilarity{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arg1 = do_dynamic_expr(arg1, bindings, pred_embedded? || embedded?, :string)
    arg2 = do_dynamic_expr(arg2, bindings, pred_embedded? || embedded?)

    Ecto.Query.dynamic(fragment("similarity(?, ?)", ^arg1, ^arg2))
  end

  defp do_dynamic_expr(
         %IsNil{left: left, right: right, embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    left_expr = do_dynamic_expr(left, bindings, pred_embedded? || embedded?)
    right_expr = do_dynamic_expr(right, bindings, pred_embedded? || embedded?)
    Ecto.Query.dynamic(is_nil(^left_expr) == ^right_expr)
  end

  defp do_dynamic_expr(
         %Ago{arguments: [left, right], embedded?: _pred_embedded?},
         _bindings,
         _embedded?,
         _type
       )
       when is_integer(left) and (is_binary(right) or is_atom(right)) do
    Ecto.Query.dynamic(datetime_add(^DateTime.utc_now(), ^left * -1, ^to_string(right)))
  end

  defp do_dynamic_expr(
         %Contains{arguments: [left, %Ash.CiString{} = right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
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
         %Contains{arguments: [left, right], embedded?: pred_embedded?},
         bindings,
         embedded?,
         type
       ) do
    do_dynamic_expr(
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "strpos(",
          expr: left,
          raw: ", ",
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

    condition = do_dynamic_expr(condition, bindings, pred_embedded? || embedded?, condition_type)

    when_true = do_dynamic_expr(when_true, bindings, pred_embedded? || embedded?, when_true_type)

    when_false =
      do_dynamic_expr(
        when_false,
        bindings,
        pred_embedded? || embedded?,
        when_false_type
      )

    do_dynamic_expr(
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

  defp do_dynamic_expr(
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

    {params, fragment_data} =
      Enum.reduce(arguments, {[], []}, fn
        {:raw, str}, {params, fragment_data} ->
          {params, fragment_data ++ [{:raw, str}]}

        {:casted_expr, expr}, {params, fragment_data} ->
          {params ++ [{expr, :any}], fragment_data ++ [{:expr, {:^, [], [Enum.count(params)]}}]}

        {:expr, expr}, {params, fragment_data} ->
          expr = do_dynamic_expr(expr, bindings, pred_embedded? || embedded?)
          {params ++ [{expr, :any}], fragment_data ++ [{:expr, {:^, [], [Enum.count(params)]}}]}
      end)

    %Ecto.Query.DynamicExpr{
      fun: fn _query ->
        {{:fragment, [], fragment_data}, params, []}
      end,
      binding: [],
      file: __ENV__.file,
      line: __ENV__.line
    }
  end

  defp do_dynamic_expr(
         %BooleanExpression{op: op, left: left, right: right},
         bindings,
         embedded?,
         _type
       ) do
    left_expr = do_dynamic_expr(left, bindings, embedded?)
    right_expr = do_dynamic_expr(right, bindings, embedded?)

    case op do
      :and ->
        Ecto.Query.dynamic(^left and ^right)

      :or ->
        Ecto.Query.dynamic(^left or ^right)
    end

    {op, [], [left_expr, right_expr]}
  end

  defp do_dynamic_expr(
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
    [left_type, right_type] = AshPostgres.Types.determine_types(mod, [left, right])

    left_expr = do_dynamic_expr(left, bindings, pred_embedded? || embedded?, left_type)

    right_expr = do_dynamic_expr(right, bindings, pred_embedded? || embedded?, right_type)

    case operator do
      :== ->
        Ecto.Query.dynamic(^left_expr == ^right_expr)

      :> ->
        Ecto.Query.dynamic(^left_expr > ^right_expr)

      :< ->
        Ecto.Query.dynamic(^left_expr < ^right_expr)

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
          %Fragment{
            embedded?: pred_embedded?,
            arguments: [
              casted_expr: left_expr,
              raw: " || ",
              casted_expr: right_expr
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

  defp do_dynamic_expr(%MapSet{} = mapset, bindings, embedded?, type) do
    do_dynamic_expr(Enum.to_list(mapset), bindings, embedded?, type)
  end

  defp do_dynamic_expr(%Ash.CiString{string: string}, bindings, embedded?, type) do
    string = do_dynamic_expr(string, bindings, embedded?)

    do_dynamic_expr(
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
         %Ref{
           attribute: %Ash.Query.Calculation{} = calculation,
           relationship_path: [],
           resource: resource
         },
         bindings,
         embedded?,
         type
       ) do
    calculation = %{calculation | load: calculation.name}

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
        do_dynamic_expr(
          expression,
          bindings,
          embedded?,
          type
        )

      {:error, _error} ->
        raise "Failed to hydrate references in #{inspect(calculation.module.expression(calculation.opts, calculation.context))}"
    end
  end

  defp do_dynamic_expr(
         %Ref{attribute: %Ash.Query.Aggregate{} = aggregate} = ref,
         bindings,
         _embedded?,
         _type
       ) do
    ref_binding = ref_binding(ref, bindings)
    expr = Ecto.Query.dynamic(field(as(^ref_binding), ^aggregate.name))

    type = AshPostgres.Types.parameterized_type(aggregate.type, [])

    type =
      if aggregate.kind == :list do
        {:array, type}
      else
        type
      end

    if aggregate.default_value do
      Ecto.Query.dynamic(coalesce(^expr, type(^aggregate.default_value, ^type)))
    else
      expr
    end
  end

  defp do_dynamic_expr(
         %Ref{
           attribute: %Ash.Query.Calculation{} = calculation,
           relationship_path: relationship_path
         } = ref,
         bindings,
         embedded?,
         type
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
        hydrated
        |> Ash.Filter.update_aggregates(fn aggregate, _ ->
          %{aggregate | relationship_path: []}
        end)
        |> do_dynamic_expr(
          %{bindings | bindings: temp_bindings},
          embedded?,
          type
        )

      _ ->
        raise "Failed to hydrate references in #{inspect(calculation.module.expression(calculation.opts, calculation.context))}"
    end
  end

  defp do_dynamic_expr(
         %Type{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arg1 = do_dynamic_expr(arg1, bindings, false)
    arg2 = do_dynamic_expr(arg2, bindings, pred_embedded? || embedded?)

    Ecto.Query.dynamic(type(^arg1, ^AshPostgres.Types.parameterized_type(arg2, [])))
  end

  defp do_dynamic_expr(
         %Type{arguments: [arg1, arg2, constraints], embedded?: pred_embedded?},
         bindings,
         embedded?,
         _type
       ) do
    arg1 = do_dynamic_expr(arg1, bindings, false)
    arg2 = do_dynamic_expr(arg2, bindings, pred_embedded? || embedded?)

    Ecto.Query.dynamic(type(^arg1, ^AshPostgres.Types.parameterized_type(arg2, constraints)))
  end

  defp do_dynamic_expr(
         %Ref{attribute: %Ash.Resource.Attribute{name: name}} = ref,
         bindings,
         _embedded?,
         _type
       ) do
    ref_binding = ref_binding(ref, bindings)
    Ecto.Query.dynamic(field(as(^ref_binding), ^name))
  end

  defp do_dynamic_expr(other, _bindings, true, _type) do
    other
  end

  defp do_dynamic_expr(value, _bindings, false, {:in, type}) when is_list(value) do
    Ecto.Query.dynamic(type(^value, ^{:array, type}))
  end

  defp do_dynamic_expr(value, bindings, false, type)
       when is_atom(value) and not is_boolean(value) do
    do_dynamic_expr(to_string(value), bindings, false, type)
  end

  defp do_dynamic_expr(value, _bindings, false, type) when type == nil or type == :any do
    Ecto.Query.dynamic(^value)
  end

  defp do_dynamic_expr(value, _bindings, false, type) do
    Ecto.Query.dynamic(type(^value, ^type))
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

  defp ref_binding(
         %{attribute: %Ash.Query.Calculation{}} = ref,
         bindings
       ) do
    Enum.find_value(bindings.bindings, fn {binding, data} ->
      data.path == ref.relationship_path && data.type in [:inner, :left, :root] && binding
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
end
