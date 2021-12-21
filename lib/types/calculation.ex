defmodule AshPostgres.Calculation do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  def add_calculation(query, calculation, expression, resource) do
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    query =
      if query.select do
        query
      else
        from(row in query,
          select: row,
          select_merge: %{aggregates: %{}, calculations: %{}}
        )
      end

    expr =
      AshPostgres.Expr.dynamic_expr(
        expression,
        query.__ash_bindings__
      )

    {:ok,
     query
     |> Map.update!(:select, &add_to_calculation_select(&1, expr, calculation))}
  end

  defp add_to_calculation_select(
         %{
           expr:
             {:merge, _,
              [
                first,
                {:%{}, _,
                 [{:aggregates, {:%{}, [], agg_fields}}, {:calculations, {:%{}, [], fields}}]}
              ]}
         } = select,
         expr,
         %{load: nil} = calculation
       ) do
    field = expr |> IO.inspect()

    name =
      if calculation.sequence == 0 do
        calculation.name
      else
        String.to_existing_atom("#{calculation.name}_#{calculation.sequence}")
      end

    new_fields = [
      {name, field}
      | fields
    ]

    %{
      select
      | expr:
          {:merge, [],
           [
             first,
             {:%{}, [],
              [{:aggregates, {:%{}, [], agg_fields}}, {:calculations, {:%{}, [], new_fields}}]}
           ]}
    }
  end

  defp add_to_calculation_select(
         %{expr: select_expr} = select,
         expr,
         %{load: load_as} = calculation
       ) do
    field =
      Ecto.Query.dynamic(type(^expr, ^AshPostgres.Types.parameterized_type(calculation.type, [])))

    load_as =
      if calculation.sequence == 0 do
        load_as
      else
        "#{load_as}_#{calculation.sequence}"
      end

    %{
      select
      | expr: {:merge, [], [select_expr, {:%{}, [], [{load_as, field}]}]}
    }
  end
end
