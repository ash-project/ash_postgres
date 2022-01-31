defmodule AshPostgres.Calculation do
  @moduledoc false

  require Ecto.Query

  def add_calculations(query, [], _), do: {:ok, query}

  def add_calculations(query, calculations, resource) do
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    query =
      if query.select do
        query
      else
        Ecto.Query.select_merge(query, %{})
      end

    dynamics =
      Enum.map(calculations, fn {calculation, expression} ->
        expr =
          AshPostgres.Expr.dynamic_expr(
            query,
            expression,
            query.__ash_bindings__
          )

        {calculation.load, calculation.name, expr}
      end)

    {:ok, add_calculation_selects(query, dynamics)}
  end

  defp add_calculation_selects(query, dynamics) do
    {in_aggregates, in_body} =
      Enum.split_with(dynamics, fn {load, _name, _dynamic} -> is_nil(load) end)

    query =
      if query.select do
        query
      else
        Ecto.Query.select(query, %{})
      end

    {exprs, new_params, _} =
      Enum.reduce(
        in_body,
        {[], Enum.reverse(query.select.params), Enum.count(query.select.params)},
        fn {load, _, dynamic}, {exprs, params, count} ->
          {expr, new_params, count} =
            Ecto.Query.Builder.Dynamic.partially_expand(
              :select,
              query,
              dynamic,
              params,
              count
            )

          {[{load, expr} | exprs], new_params, count}
        end
      )

    query = %{
      query
      | select: %{
          query.select
          | expr: {:merge, [], [query.select.expr, {:%{}, [], exprs}]},
            params: Enum.reverse(new_params)
        }
    }

    add_calculations_in_calculations(query, in_aggregates)
  end

  defp add_calculations_in_calculations(query, []), do: query

  defp add_calculations_in_calculations(
         %{select: %{expr: expr} = select} = query,
         in_calculations
       ) do
    {exprs, new_params, _} =
      Enum.reduce(
        in_calculations,
        {[], Enum.reverse(query.select.params), Enum.count(query.select.params)},
        fn {load, _, dynamic}, {exprs, params, count} ->
          {expr, new_params, count} =
            Ecto.Query.Builder.Dynamic.partially_expand(
              :select,
              query,
              dynamic,
              params,
              count
            )

          {[{load, expr} | exprs], new_params, count}
        end
      )

    %{
      query
      | select: %{
          select
          | expr: {:merge, [], [expr, {:%{}, [], [calculations: {:%{}, [], exprs}]}]},
            params: Enum.reverse(new_params)
        }
    }
  end
end
