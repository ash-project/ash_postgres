defmodule AshPostgres.SqlImplementation do
  @moduledoc false
  use AshSql.Implementation

  require Ecto.Query

  @impl true
  def manual_relationship_function, do: :ash_postgres_join

  @impl true
  def manual_relationship_subquery_function, do: :ash_postgres_subquery

  @impl true
  def require_ash_functions_for_or_and_and?, do: true

  @impl true
  def require_extension_for_citext, do: {true, "citext"}

  @impl true
  def expr(
        query,
        %like{arguments: [arg1, arg2], embedded?: pred_embedded?},
        bindings,
        embedded?,
        acc,
        type
      )
      when like in [AshPostgres.Functions.Like, AshPostgres.Functions.ILike] do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    inner_dyn =
      if like == AshPostgres.Functions.Like do
        Ecto.Query.dynamic(like(^arg1, ^arg2))
      else
        Ecto.Query.dynamic(ilike(^arg1, ^arg2))
      end

    if type != Ash.Type.Boolean do
      {:ok, inner_dyn, acc}
    else
      {:ok, Ecto.Query.dynamic(type(^inner_dyn, ^type)), acc}
    end
  end

  def expr(
        query,
        %AshPostgres.Functions.TrigramSimilarity{
          arguments: [arg1, arg2],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        _type
      ) do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    {:ok, Ecto.Query.dynamic(fragment("similarity(?, ?)", ^arg1, ^arg2)), acc}
  end

  def expr(
        query,
        %AshPostgres.Functions.VectorCosineDistance{
          arguments: [arg1, arg2],
          embedded?: pred_embedded?
        },
        bindings,
        embedded?,
        acc,
        _type
      ) do
    {arg1, acc} =
      AshSql.Expr.dynamic_expr(query, arg1, bindings, pred_embedded? || embedded?, :string, acc)

    {arg2, acc} =
      AshSql.Expr.dynamic_expr(query, arg2, bindings, pred_embedded? || embedded?, :string, acc)

    {:ok, Ecto.Query.dynamic(fragment("(? <=> ?)", ^arg1, ^arg2)), acc}
  end

  def expr(
        _query,
        _expr,
        _bindings,
        _embedded?,
        _acc,
        _type
      ) do
    :error
  end

  @impl true
  def table(resource) do
    AshPostgres.DataLayer.Info.table(resource)
  end

  @impl true
  def schema(resource) do
    AshPostgres.DataLayer.Info.schema(resource)
  end

  @impl true
  def repo(resource, kind) do
    AshPostgres.DataLayer.Info.repo(resource, kind)
  end

  @impl true
  def simple_join_first_aggregates(resource) do
    AshPostgres.DataLayer.Info.simple_join_first_aggregates(resource)
  end

  @impl true
  def list_aggregate(resource) do
    if AshPostgres.DataLayer.Info.pg_version_matches?(resource, ">= 16.0.0") do
      "any_value"
    else
      "array_agg"
    end
  end

  @impl true
  def parameterized_type(type, constraints, no_maps? \\ true)

  def parameterized_type({:parameterized, _} = type, _, _) do
    type
  end

  def parameterized_type({:parameterized, _, _} = type, _, _) do
    type
  end

  def parameterized_type({:in, type}, constraints, no_maps?) do
    parameterized_type({:array, type}, constraints, no_maps?)
  end

  def parameterized_type({:array, type}, constraints, _) do
    case parameterized_type(type, constraints[:items] || [], false) do
      nil ->
        nil

      type ->
        {:array, type}
    end
  end

  def parameterized_type(Ash.Type.CiString, constraints, no_maps?) do
    parameterized_type(AshPostgres.Type.CiStringWrapper, constraints, no_maps?)
  end

  def parameterized_type(Ash.Type.String, constraints, no_maps?) do
    parameterized_type(AshPostgres.Type.StringWrapper, constraints, no_maps?)
  end

  def parameterized_type(:tsquery, constraints, no_maps?) do
    parameterized_type(AshPostgres.Tsquery, constraints, no_maps?)
  end

  def parameterized_type(type, _constraints, false)
      when type in [Ash.Type.Map, Ash.Type.Map.EctoType],
      do: :map

  def parameterized_type(type, _constraints, true)
      when type in [Ash.Type.Map, Ash.Type.Map.EctoType],
      do: nil

  def parameterized_type(type, constraints, no_maps?) do
    if Ash.Type.ash_type?(type) do
      cast_in_query? =
        if function_exported?(Ash.Type, :cast_in_query?, 2) do
          Ash.Type.cast_in_query?(type, constraints)
        else
          Ash.Type.cast_in_query?(type)
        end

      if cast_in_query? do
        type = Ash.Type.ecto_type(type)

        parameterized_type(type, constraints, no_maps?)
      else
        nil
      end
    else
      if is_atom(type) && :erlang.function_exported(type, :type, 1) do
        type =
          if type == :ci_string do
            :citext
          else
            type
          end

        Ecto.ParameterizedType.init(type, constraints || [])
      else
        type
      end
    end
  end

  @impl true
  def determine_types(mod, values) do
    Code.ensure_compiled(mod)

    name =
      cond do
        function_exported?(mod, :operator, 0) ->
          mod.operator()

        function_exported?(mod, :name, 0) ->
          mod.name()

        true ->
          nil
      end

    cond do
      :erlang.function_exported(mod, :types, 0) ->
        mod.types()

      :erlang.function_exported(mod, :args, 0) ->
        mod.args()

      true ->
        [:any]
    end
    |> Enum.concat(Map.keys(Ash.Query.Operator.operator_overloads(name) || %{}))
    |> Enum.map(fn types ->
      case types do
        :same ->
          types =
            for _ <- values do
              :same
            end

          closest_fitting_type(types, values)

        :any ->
          for _ <- values do
            :any
          end

        types ->
          closest_fitting_type(types, values)
      end
    end)
    |> Enum.filter(fn types ->
      Enum.all?(types, &(vagueness(&1) == 0))
    end)
    |> case do
      [type] ->
        if type == :any || type == {:in, :any} do
          nil
        else
          type
        end

      # There are things we could likely do here
      # We only say "we know what types these are" when we explicitly know
      _ ->
        Enum.map(values, fn _ -> nil end)
    end
  end

  defp closest_fitting_type(types, values) do
    types_with_values = Enum.zip(types, values)

    types_with_values
    |> fill_in_known_types()
    |> clarify_types()
  end

  defp clarify_types(types) do
    basis =
      types
      |> Enum.map(&elem(&1, 0))
      |> Enum.min_by(&vagueness(&1))

    Enum.map(types, fn {type, _value} ->
      replace_same(type, basis)
    end)
  end

  defp replace_same({:in, type}, basis) do
    {:in, replace_same(type, basis)}
  end

  defp replace_same(:same, :same) do
    :any
  end

  defp replace_same(:same, {:in, :same}) do
    {:in, :any}
  end

  defp replace_same(:same, basis) do
    basis
  end

  defp replace_same(other, _basis) do
    other
  end

  defp fill_in_known_types(types) do
    Enum.map(types, &fill_in_known_type/1)
  end

  defp fill_in_known_type(
         {{:array, type},
          %Ash.Query.Function.Type{arguments: [inner, {:array, type}, constraints]} = func}
       ) do
    {:in,
     fill_in_known_type({type, %{func | arguments: [inner, type, constraints[:items] || []]}})}
  end

  defp fill_in_known_type(
         {{:array, type},
          %Ash.Query.Ref{attribute: %{type: {:array, type}, constraints: constraints} = attribute} =
            ref}
       ) do
    {:in,
     fill_in_known_type(
       {type,
        %{ref | attribute: %{attribute | type: type, constraints: constraints[:items] || []}}}
     )}
  end

  defp fill_in_known_type(
         {vague_type, %Ash.Query.Function.Type{arguments: [_, type, constraints]}} = func
       )
       when vague_type in [:any, :same] do
    if Ash.Type.ash_type?(type) do
      type = type |> parameterized_type(constraints) |> array_to_in()

      {type || :any, func}
    else
      type =
        if is_atom(type) && :erlang.function_exported(type, :type, 1) do
          Ecto.ParameterizedType.init(type, []) |> array_to_in()
        else
          type |> array_to_in()
        end

      {type, func}
    end
  end

  defp fill_in_known_type(
         {vague_type, %Ash.Query.Ref{attribute: %{type: type, constraints: constraints}}} = ref
       )
       when vague_type in [:any, :same] do
    if Ash.Type.ash_type?(type) do
      type = type |> parameterized_type(constraints) |> array_to_in()

      {type || :any, ref}
    else
      type =
        if is_atom(type) && :erlang.function_exported(type, :type, 1) do
          Ecto.ParameterizedType.init(type, []) |> array_to_in()
        else
          type |> array_to_in()
        end

      {type, ref}
    end
  end

  defp fill_in_known_type({type, value}), do: {array_to_in(type), value}

  defp array_to_in({:array, v}), do: {:in, array_to_in(v)}

  defp array_to_in(v), do: v

  defp vagueness({:in, type}), do: vagueness(type)
  defp vagueness(:same), do: 2
  defp vagueness(:any), do: 1
  defp vagueness(_), do: 0
end
