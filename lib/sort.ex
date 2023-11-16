defmodule AshPostgres.Sort do
  @moduledoc false
  require Ecto.Query

  def sort(
        query,
        sort,
        resource,
        relationship_path \\ [],
        binding \\ 0,
        type \\ :window
      ) do
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    used_aggregates =
      Enum.flat_map(sort, fn
        {%Ash.Query.Calculation{} = calculation, _} ->
          case Ash.Filter.hydrate_refs(
                 calculation.module.expression(calculation.opts, calculation.context),
                 %{
                   resource: resource,
                   aggregates: %{},
                   parent_stack: query.__ash_bindings__[:parent_resources] || [],
                   calculations: %{},
                   public?: false
                 }
               ) do
            {:ok, hydrated} ->
              Ash.Filter.used_aggregates(hydrated)

            _ ->
              []
          end

        {key, _} ->
          case Ash.Resource.Info.aggregate(resource, key) do
            nil ->
              []

            aggregate ->
              [aggregate]
          end

        _ ->
          []
      end)

    calcs =
      Enum.flat_map(sort, fn
        {%Ash.Query.Calculation{} = calculation, _} ->
          [calculation]

        _ ->
          []
      end)

    {:ok, query} =
      AshPostgres.Join.join_all_relationships(
        query,
        %Ash.Filter{
          resource: resource,
          expression: calcs
        },
        left_only?: true
      )

    case AshPostgres.Aggregate.add_aggregates(query, used_aggregates, resource, false, 0) do
      {:error, error} ->
        {:error, error}

      {:ok, query} ->
        sort
        |> sanitize_sort()
        |> Enum.reduce_while({:ok, []}, fn
          {order, %Ash.Query.Calculation{} = calc}, {:ok, query_expr} ->
            type =
              if calc.type do
                AshPostgres.Types.parameterized_type(calc.type, calc.constraints)
              else
                nil
              end

            calc.opts
            |> calc.module.expression(calc.context)
            |> Ash.Filter.hydrate_refs(%{
              resource: resource,
              aggregates: query.__ash_bindings__.aggregate_defs,
              parent_stack: query.__ash_bindings__[:parent_resources] || [],
              calculations: %{},
              public?: false
            })
            |> Ash.Filter.move_to_relationship_path(relationship_path)
            |> case do
              {:ok, expr} ->
                bindings =
                  if query.__ash_bindings__[:parent_bindings] do
                    Map.update!(query.__ash_bindings__, :parent_bindings, fn parent ->
                      Map.put(parent, :parent_is_parent_as?, false)
                    end)
                  else
                    query.__ash_bindings__
                  end

                expr =
                  AshPostgres.Expr.dynamic_expr(
                    query,
                    expr,
                    bindings,
                    false,
                    type
                  )

                {:cont, {:ok, query_expr ++ [{order, expr}]}}

              {:error, error} ->
                {:halt, {:error, error}}
            end

          {order, sort}, {:ok, query_expr} ->
            expr =
              case find_aggregate_binding(
                     query.__ash_bindings__.bindings,
                     relationship_path,
                     sort
                   ) do
                {:ok, binding} ->
                  aggregate =
                    Ash.Resource.Info.aggregate(resource, sort) ||
                      raise "No such aggregate for query aggregate #{inspect(sort)}"

                  {:ok, attribute_type} =
                    if aggregate.field do
                      related = Ash.Resource.Info.related(resource, aggregate.relationship_path)

                      attr = Ash.Resource.Info.attribute(related, aggregate.field)

                      if attr && related do
                        {:ok, AshPostgres.Types.parameterized_type(attr.type, attr.constraints)}
                      else
                        {:ok, nil}
                      end
                    else
                      {:ok, nil}
                    end

                  default_value =
                    aggregate.default || Ash.Query.Aggregate.default_value(aggregate.kind)

                  if is_nil(default_value) do
                    Ecto.Query.dynamic(field(as(^binding), ^sort))
                  else
                    if attribute_type do
                      Ecto.Query.dynamic(
                        coalesce(
                          field(as(^binding), ^sort),
                          type(^default_value, ^attribute_type)
                        )
                      )
                    else
                      Ecto.Query.dynamic(coalesce(field(as(^binding), ^sort), ^default_value))
                    end
                  end

                :error ->
                  aggregate = Ash.Resource.Info.aggregate(resource, sort)

                  {binding, sort} =
                    if aggregate &&
                         AshPostgres.Aggregate.optimizable_first_aggregate?(resource, aggregate) do
                      {AshPostgres.Join.get_binding(
                         resource,
                         aggregate.relationship_path,
                         query,
                         [
                           :left,
                           :inner
                         ]
                       ), aggregate.field}
                    else
                      {binding, sort}
                    end

                  Ecto.Query.dynamic(field(as(^binding), ^sort))
              end

            {:cont, {:ok, query_expr ++ [{order, expr}]}}
        end)
        |> case do
          {:ok, []} ->
            if type == :return do
              {:ok, [], query}
            else
              {:ok, query}
            end

          {:ok, sort_exprs} ->
            case type do
              :return ->
                {:ok, order_to_fragments(sort_exprs), query}

              :window ->
                new_query = Ecto.Query.order_by(query, ^sort_exprs)

                sort_expr = List.last(new_query.order_bys)

                new_query =
                  new_query
                  |> Map.update!(:windows, fn windows ->
                    order_by_expr = %{sort_expr | expr: [order_by: sort_expr.expr]}
                    Keyword.put(windows, :order, order_by_expr)
                  end)
                  |> Map.update!(:__ash_bindings__, &Map.put(&1, :__order__?, true))

                {:ok, new_query}

              :direct ->
                {:ok, query |> Ecto.Query.order_by(^sort_exprs) |> set_sort_applied()}
            end

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp set_sort_applied(query) do
    Map.update!(query, :__ash_bindings__, &Map.put(&1, :sort_applied?, true))
  end

  def find_aggregate_binding(bindings, relationship_path, sort) do
    Enum.find_value(
      bindings,
      :error,
      fn
        {key, %{type: :aggregate, path: ^relationship_path, aggregates: aggregates}} ->
          if Enum.any?(aggregates, &(&1.name == sort)) do
            {:ok, key}
          end

        _ ->
          nil
      end
    )
  end

  def order_to_fragments([]), do: []

  def order_to_fragments(order) when is_list(order) do
    Enum.map(order, &do_order_to_fragments(&1))
  end

  def do_order_to_fragments({order, sort}) do
    case order do
      :asc ->
        Ecto.Query.dynamic([row], fragment("? ASC", ^sort))

      :desc ->
        Ecto.Query.dynamic([row], fragment("? DESC", ^sort))

      :asc_nulls_last ->
        Ecto.Query.dynamic([row], fragment("? ASC NULLS LAST", ^sort))

      :asc_nulls_first ->
        Ecto.Query.dynamic([row], fragment("? ASC NULLS FIRST", ^sort))

      :desc_nulls_first ->
        Ecto.Query.dynamic([row], fragment("? DESC NULLS FIRST", ^sort))

      :desc_nulls_last ->
        Ecto.Query.dynamic([row], fragment("? DESC NULLS LAST", ^sort))
        "DESC NULLS LAST"
    end
  end

  def order_to_postgres_order(dir) do
    case dir do
      :asc -> nil
      :asc_nils_last -> " ASC NULLS LAST"
      :asc_nils_first -> " ASC NULLS FIRST"
      :desc -> " DESC"
      :desc_nils_last -> " DESC NULLS LAST"
      :desc_nils_first -> " DESC NULLS FIRST"
    end
  end

  defp sanitize_sort(sort) do
    sort
    |> List.wrap()
    |> Enum.map(fn
      {sort, {order, context}} ->
        {ash_to_ecto_order(order), {sort, context}}

      {sort, order} ->
        {ash_to_ecto_order(order), sort}

      sort ->
        sort
    end)
  end

  defp ash_to_ecto_order(:asc_nils_last), do: :asc_nulls_last
  defp ash_to_ecto_order(:asc_nils_first), do: :asc_nulls_first
  defp ash_to_ecto_order(:desc_nils_last), do: :desc_nulls_last
  defp ash_to_ecto_order(:desc_nils_first), do: :desc_nulls_first
  defp ash_to_ecto_order(other), do: other
end
