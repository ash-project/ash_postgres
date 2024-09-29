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
  def storage_type(resource, field) do
    case AshPostgres.DataLayer.Info.storage_types(resource)[field] do
      nil ->
        nil

      {:array, type} ->
        parameterized_type({:array, Ash.Type.get_type(type)}, [], false)

      {:array, type, constraints} ->
        parameterized_type({:array, Ash.Type.get_type(type)}, constraints, false)

      {type, constraints} ->
        parameterized_type(type, constraints, false)

      type ->
        parameterized_type(type, [], false)
    end
  end

  @impl true
  def expr(_query, [], _bindings, _embedded?, acc, type) when type in [:map, :jsonb] do
    {:ok, Ecto.Query.dynamic(fragment("'[]'::jsonb")), acc}
  end

  def expr(
        query,
        %Ash.Query.UpsertConflict{attribute: attribute},
        _bindings,
        _embedded?,
        acc,
        _type
      ) do
    query.__ash_bindings__.resource

    {:ok,
     Ecto.Query.dynamic(
       [],
       fragment(
         "EXCLUDED.?",
         literal(
           ^to_string(
             AshPostgres.DataLayer.get_source_for_upsert_field(
               attribute,
               query.__ash_bindings__.resource
             )
           )
         )
       )
     ), acc}
  end

  def expr(query, %AshPostgres.Functions.Binding{}, _bindings, _embedded?, acc, _type) do
    binding =
      AshSql.Bindings.get_binding(
        query.__ash_bindings__.resource,
        [],
        query,
        [:left, :inner, :root]
      )

    if is_nil(binding) do
      raise "Error while constructing explicit `binding()` reference."
    end

    {:ok, Ecto.Query.dynamic([{^binding, row}], row), acc}
  end

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
    if type == :array do
      raise "WHAT"
    end

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
        if type == :ci_string do
          :citext
        else
          case type.type(constraints || []) do
            :ci_string ->
              parameterized_type(AshPostgres.Type.CiStringWrapper, constraints, no_maps?)

            _ ->
              Ecto.ParameterizedType.init(type, constraints || [])
          end
        end
      else
        if type == :ci_string do
          :citext
        else
          type
        end
      end
    end
  end

  @impl true
  def determine_types(mod, args, returns \\ nil) do
    {types, new_returns} = Ash.Expr.determine_types(mod, args, returns)

    new_returns =
      case new_returns do
        {:parameterized, _} = parameterized -> parameterized
        {:array, _} = type -> parameterized_type(type, [])
        {type, constraints} -> parameterized_type(type, constraints)
        other -> other
      end

    {Enum.map(types, fn
       {:parameterized, _} = parameterized ->
         parameterized

       {:array, _} = type ->
         parameterized_type(type, [])

       {type, constraints} ->
         parameterized_type(type, constraints)

       other ->
         other
     end), new_returns || returns}
  end
end
