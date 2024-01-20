defmodule AshPostgres.Calculation do
  @moduledoc false

  require Ecto.Query

  @next_calculation_names Enum.reduce(0..999, %{}, fn i, acc ->
                            Map.put(acc, :"calculation_#{i}", :"calculation_#{i + 1}")
                          end)

  def add_calculations(query, [], _, _, _select?), do: {:ok, query}

  def add_calculations(query, calculations, resource, source_binding, select?) do
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    {:ok, query} =
      AshPostgres.Join.join_all_relationships(
        query,
        %Ash.Filter{
          resource: resource,
          expression: Enum.map(calculations, &elem(&1, 1))
        },
        left_only?: true
      )

    aggregates =
      calculations
      |> Enum.flat_map(fn {calculation, expression} ->
        expression
        |> Ash.Filter.used_aggregates([])
        |> Enum.map(&Map.put(&1, :context, calculation.context))
      end)
      |> Enum.uniq()

    {query, calculations} =
      Enum.reduce(
        calculations,
        {query, []},
        fn {calculation, expression}, {query, calculations} ->
          if is_atom(calculation.name) do
            {query, [{calculation, expression} | calculations]}
          else
            {query, name} = use_calculation_name(query, calculation.name)

            {query, [{%{calculation | name: name}, expression} | calculations]}
          end
        end
      )

    case AshPostgres.Aggregate.add_aggregates(
           query,
           aggregates,
           query.__ash_bindings__.resource,
           false,
           source_binding
         ) do
      {:ok, query} ->
        if select? do
          query =
            if query.select do
              query
            else
              Ecto.Query.select_merge(query, %{})
            end

          {dynamics, query} =
            Enum.reduce(calculations, {[], query}, fn {calculation, expression}, {list, query} ->
              type =
                AshPostgres.Types.parameterized_type(
                  calculation.type,
                  Map.get(calculation, :constraints, [])
                )

              expression =
                Ash.Actions.Read.add_calc_context_to_filter(
                  expression,
                  calculation.context[:actor],
                  calculation.context[:authorize?],
                  calculation.context[:tenant],
                  calculation.context[:tracer]
                )

              {expr, acc} =
                AshPostgres.Expr.dynamic_expr(
                  query,
                  expression,
                  query.__ash_bindings__,
                  false,
                  type
                )

              expr =
                if type do
                  Ecto.Query.dynamic(type(^expr, ^type))
                else
                  expr
                end

              {[{calculation.load, calculation.name, expr} | list],
               AshPostgres.DataLayer.merge_expr_accumulator(query, acc)}
            end)

          {:ok, add_calculation_selects(query, dynamics)}
        else
          {:ok, query}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  def next_calculation_name(i) do
    @next_calculation_names[i] ||
      raise Ash.Error.Framework.AssumptionFailed,
        message: """
        All 1000 static names for calculations have been used in a single query.
        Congratulations, this means that you have gone so wildly beyond our imagination
        of how much can fit into a single quer. Please file an issue and we will raise the limit.
        """
  end

  defp use_calculation_name(query, aggregate_name) do
    {%{
       query
       | __ash_bindings__: %{
           query.__ash_bindings__
           | current_calculation_name:
               next_calculation_name(query.__ash_bindings__.current_calculation_name),
             calculation_names:
               Map.put(
                 query.__ash_bindings__.calculation_names,
                 aggregate_name,
                 query.__ash_bindings__.current_calculation_name
               )
         }
     }, query.__ash_bindings__.current_calculation_name}
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
