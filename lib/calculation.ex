defmodule AshPostgres.Calculation do
  @moduledoc false

  require Ecto.Query

  def add_calculations(query, [], _, _), do: {:ok, query}

  def add_calculations(query, calculations, resource, source_binding) do
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    aggregates =
      calculations
      |> Enum.flat_map(fn {_calculation, expression} ->
        used_calculations =
          Ash.Filter.used_calculations(
            expression,
            query.__ash_bindings__.resource,
            []
          )

        AshPostgres.Aggregate.used_aggregates(
          expression,
          query.__ash_bindings__.resource,
          used_calculations,
          []
        )
      end)
      |> Enum.uniq()

    case AshPostgres.Aggregate.add_aggregates(
           query,
           aggregates,
           query.__ash_bindings__.resource,
           false,
           source_binding
         ) do
      {:ok, query} ->
        query =
          if query.select do
            query
          else
            Ecto.Query.select_merge(query, %{})
          end

        dynamics =
          Enum.map(calculations, fn {calculation, expression} ->
            type =
              AshPostgres.Types.parameterized_type(
                calculation.type,
                Map.get(calculation, :constraints, [])
              )

            expr =
              AshPostgres.Expr.dynamic_expr(
                query,
                expression,
                query.__ash_bindings__,
                false,
                type
              )

            expr = Ecto.Query.dynamic(type(^expr, ^type))

            {calculation.load, calculation.name, expr}
          end)

        {:ok, add_calculation_selects(query, dynamics)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp add_calculation_selects(query, dynamics) do
    {in_calculations, in_body} =
      Enum.split_with(dynamics, fn {load, _name, _dynamic} -> is_nil(load) end)

    calcs =
      in_body
      |> Map.new(fn {load, _, dynamic} ->
        {load, dynamic}
      end)

    calcs =
      if Enum.empty?(in_calculations) do
        calcs
      else
        Map.put(
          calcs,
          :calculations,
          Map.new(in_calculations, fn {_, name, dynamic} ->
            {name, dynamic}
          end)
        )
      end

    Ecto.Query.select_merge(query, ^calcs)
  end
end
