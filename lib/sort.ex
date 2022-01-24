defmodule AshPostgres.Sort do
  @moduledoc false
  require Ecto.Query

  def sort(query, sort, resource) do
    {:ok, query}
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    sort
    |> sanitize_sort()
    |> Enum.reduce_while({:ok, []}, fn
      {order, %Ash.Query.Calculation{} = calc}, {:ok, query_expr} ->
        type =
          if calc.type do
            AshPostgres.Types.parameterized_type(calc.type, [])
          else
            nil
          end

        calc.opts
        |> calc.module.expression(calc.context)
        |> Ash.Filter.hydrate_refs(%{
          resource: resource,
          aggregates: query.__ash_bindings__.aggregate_defs,
          calculations: %{},
          public?: false
        })
        |> case do
          {:ok, expr} ->
            expr = AshPostgres.Expr.dynamic_expr(query, expr, query.__ash_bindings__, false, type)

            {:cont, {:ok, query_expr ++ [{order, expr}]}}

          {:error, error} ->
            {:halt, {:error, error}}
        end

      {order, sort}, {:ok, query_expr} ->
        expr =
          case Map.fetch(query.__ash_bindings__.aggregates, sort) do
            {:ok, binding} ->
              aggregate =
                Ash.Resource.Info.aggregate(resource, sort) ||
                  raise "No such aggregate for query aggregate #{inspect(sort)}"

              {:ok, field_type} =
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
                if field_type do
                  Ecto.Query.dynamic(
                    coalesce(field(as(^binding), ^sort), type(^default_value, ^field_type))
                  )
                else
                  Ecto.Query.dynamic(coalesce(field(as(^binding), ^sort), ^default_value))
                end
              end

            :error ->
              Ecto.Query.dynamic(field(as(^0), ^sort))
          end

        {:cont, {:ok, query_expr ++ [{order, expr}]}}
    end)
    |> case do
      {:ok, []} ->
        {:ok, query}

      {:ok, sort_exprs} ->
        new_query = Ecto.Query.order_by(query, ^sort_exprs)

        sort_expr = List.last(new_query.order_bys)

        new_query =
          new_query
          |> Map.update!(:windows, fn windows ->
            order_by_expr = %{sort_expr | expr: [order_by: sort_expr.expr]}
            Keyword.put(windows, :order, order_by_expr)
          end)

        {:ok, new_query}

      {:error, error} ->
        {:error, error}
    end
  end

  def order_to_ecto([]), do: []

  def order_to_ecto(order) when is_list(order) do
    Enum.map(order, &do_order_to_ecto/1)
  end

  def do_order_to_ecto({sort, order}) do
    case order do
      :asc ->
        Ecto.Query.dynamic([row], fragment("? ASC", field(row, ^sort)))

      :desc ->
        Ecto.Query.dynamic([row], fragment("? DESC", field(row, ^sort)))

      :asc_nils_last ->
        Ecto.Query.dynamic([row], fragment("? ASC NULLS LAST", field(row, ^sort)))

      :asc_nils_first ->
        Ecto.Query.dynamic([row], fragment("? ASC NULLS FIRST", field(row, ^sort)))

      :desc_nils_first ->
        Ecto.Query.dynamic([row], fragment("? DESC NULLS FIRST", field(row, ^sort)))

      :desc_nils_last ->
        Ecto.Query.dynamic([row], fragment("? DESC NULLS LAST", field(row, ^sort)))
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
