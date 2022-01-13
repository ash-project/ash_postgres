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
        Ecto.Query.select_merge(query, %{})
      end

    query =
      Enum.reduce(in_body, query, fn {load, _, dynamic}, query ->
        Ecto.Query.select_merge(query, %{^load => ^dynamic})
      end)

    add_calculations_in_calculations(query, in_aggregates)
  end

  defp add_calculations_in_calculations(query, []), do: query

  defp add_calculations_in_calculations(
         %{select: %{expr: expr} = select} = query,
         in_calculations
       ) do
    {exprs, new_params} =
      Enum.reduce(in_calculations, {[], select.params}, fn {_load, name, dynamic},
                                                           {exprs, params} ->
        expr = {name, {:^, [], [Enum.count(params)]}}

        {[expr | exprs], params ++ [{dynamic, :any}]}
      end)

    %{
      query
      | select: %{
          select
          | expr: {:merge, [], [expr, {:%{}, [], [calculations: {:%{}, [], exprs}]}]},
            params: new_params
        }
    }
  end
end
