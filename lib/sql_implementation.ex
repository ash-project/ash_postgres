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
    |> then(fn types ->
      Enum.concat(Map.keys(Ash.Query.Operator.operator_overloads(name) || %{}), types)
    end)
    |> Enum.reject(&(&1 == :any))
    |> Enum.filter(fn typeset ->
      typeset == :same ||
        length(typeset) == length(values)
    end)
    |> Enum.find_value(Enum.map(values, fn _ -> nil end), fn typeset ->
      types_and_values =
        if typeset == :same do
          Enum.map(values, &{:same, &1})
        else
          Enum.zip(typeset, values)
        end

      types_and_values
      |> Enum.with_index()
      |> Enum.reduce_while(%{must_adopt_basis: [], basis: nil, types: []}, fn
        {{vague_type, value}, index}, acc when vague_type in [:any, :same] ->
          case determine_type(value) do
            {:ok, {type, constraints}} ->
              case acc[:basis] do
                nil ->
                  if vague_type == :any do
                    acc = Map.update!(acc, :types, &[nil | &1])
                    {:cont, Map.update!(acc, :must_adopt_basis, &[{index, fn x -> x end} | &1])}
                  else
                    acc = Map.update!(acc, :types, &[{type, constraints} | &1])
                    {:cont, Map.put(acc, :basis, {type, constraints})}
                  end

                {^type, matched_constraints} ->
                  {:cont, Map.update!(acc, :types, &[{type, matched_constraints} | &1])}

                _ ->
                  {:halt, :error}
              end

            :error ->
              acc = Map.update!(acc, :types, &[nil | &1])
              {:cont, Map.update!(acc, :must_adopt_basis, &[{index, fn x -> x end} | &1])}
          end

        {{{:array, vague_type}, value}, index}, acc when vague_type in [:any, :same] ->
          case determine_type(value) do
            {:ok, {{:array, type}, constraints}} ->
              case acc[:basis] do
                nil ->
                  if vague_type == :any do
                    acc = Map.update!(acc, :types, &[nil | &1])

                    {:cont,
                     Map.update!(
                       acc,
                       :must_adopt_basis,
                       &[
                         {index,
                          fn {type, constraints} -> {{:array, type}, items: constraints} end}
                         | &1
                       ]
                     )}
                  else
                    acc = Map.update!(acc, :types, &[{:array, {type, constraints}} | &1])
                    {:cont, Map.put(acc, :basis, {type, constraints})}
                  end

                {^type, matched_constraints} ->
                  {:cont, Map.update!(acc, :types, &[{:array, {type, matched_constraints}} | &1])}

                _ ->
                  {:halt, :error}
              end

            _ ->
              acc = Map.update!(acc, :types, &[nil | &1])

              {:cont,
               Map.update!(
                 acc,
                 :must_adopt_basis,
                 &[
                   {index, fn {type, constraints} -> {{:array, type}, items: constraints} end}
                   | &1
                 ]
               )}
          end

        {{{type, constraints}, value}, _index}, acc ->
          cond do
            !Ash.Expr.expr?(value) && !Ash.Type.matches_type?(type, value, constraints) ->
              {:halt, :error}

            Ash.Expr.expr?(value) ->
              case determine_type(value) do
                {:ok, {^type, matched_constraints}} ->
                  {:cont, Map.update!(acc, :types, &[{type, matched_constraints} | &1])}

                _ ->
                  {:halt, :error}
              end

            true ->
              {:cont, Map.update!(acc, :types, &[{type, constraints} | &1])}
          end

        {{type, value}, _index}, acc ->
          cond do
            !Ash.Expr.expr?(value) && !Ash.Type.matches_type?(type, value, []) ->
              {:halt, :error}

            Ash.Expr.expr?(value) ->
              case determine_type(value) do
                {:ok, {^type, matched_constraints}} ->
                  {:cont, Map.update!(acc, :types, &[{type, matched_constraints} | &1])}

                _ ->
                  {:halt, :error}
              end

            true ->
              {:cont, Map.update!(acc, :types, &[{type, []} | &1])}
          end
      end)
      |> case do
        :error ->
          nil

        %{basis: nil, must_adopt_basis: [], types: types} ->
          types
          |> Enum.reverse()
          |> Enum.map(fn {type, constraints} ->
            parameterized_type(type, constraints)
          end)

        %{basis: nil, must_adopt_basis: _} ->
          nil

        %{basis: basis, must_adopt_basis: basis_adopters, types: types} ->
          basis_adopters
          |> Enum.reduce(
            Enum.reverse(types),
            fn {index, function_of_basis}, types ->
              List.replace_at(types, index, function_of_basis.(basis))
            end
          )
          |> Enum.map(fn {type, constraints} ->
            parameterized_type(type, constraints)
          end)
      end
    end)
  end

  defp determine_type(value) do
    case value do
      %Ash.Query.Function.Type{arguments: [_, type, constraints]} ->
        if Ash.Type.ash_type?(type) do
          {:ok, {type, constraints}}
        else
          :error
        end

      %Ash.Query.Function.Type{arguments: [_, type]} ->
        if Ash.Type.ash_type?(type) do
          {:ok, {type, []}}
        else
          :error
        end

      %Ash.Query.Ref{attribute: %{type: type, constraints: constraints}} ->
        if Ash.Type.ash_type?(type) do
          {:ok, {type, constraints}}
        else
          :error
        end

      %Ash.Query.Ref{attribute: %{type: type}} ->
        if Ash.Type.ash_type?(type) do
          {:ok, {type, []}}
        else
          :error
        end

      _ ->
        :error
    end
  end
end
