defmodule AshPostgres.Aggregate do
  @moduledoc false

  import Ecto.Query, only: [from: 2, subquery: 1]
  require Ecto.Query

  def add_aggregates(query, aggregates, resource, select? \\ true)
  def add_aggregates(query, [], _, _), do: {:ok, query}

  def add_aggregates(query, aggregates, resource, select?) do
    resource = resource
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    result =
      Enum.reduce_while(aggregates, {:ok, query, []}, fn aggregate, {:ok, query, dynamics} ->
        if aggregate.query && !aggregate.query.valid? do
          {:halt, {:error, aggregate.query.errors}}
        else
          query_and_binding =
            case AshPostgres.DataLayer.get_binding(
                   resource,
                   aggregate.relationship_path,
                   query,
                   :aggregate
                 ) do
              nil ->
                relationship =
                  Ash.Resource.Info.relationship(resource, aggregate.relationship_path)

                if relationship.type == :many_to_many do
                  subquery = aggregate_subquery(relationship, aggregate, query)

                  case AshPostgres.Join.join_all_relationships(
                         query,
                         nil,
                         [
                           {{:aggregate, aggregate.name, subquery},
                            AshPostgres.Join.relationship_path_to_relationships(
                              resource,
                              aggregate.relationship_path
                            )}
                         ]
                       ) do
                    {:ok, new_query} ->
                      {:ok,
                       {new_query,
                        AshPostgres.DataLayer.get_binding(
                          resource,
                          aggregate.relationship_path,
                          new_query,
                          :aggregate
                        )}}

                    {:error, error} ->
                      {:error, error}
                  end
                else
                  subquery = aggregate_subquery(relationship, aggregate, query)

                  case AshPostgres.Join.join_all_relationships(
                         query,
                         nil,
                         [
                           {{:aggregate, aggregate.name, subquery},
                            AshPostgres.Join.relationship_path_to_relationships(
                              resource,
                              aggregate.relationship_path
                            )}
                         ]
                       ) do
                    {:ok, new_query} ->
                      {:ok,
                       {new_query,
                        AshPostgres.DataLayer.get_binding(
                          resource,
                          aggregate.relationship_path,
                          new_query,
                          :aggregate
                        )}}

                    {:error, error} ->
                      {:error, error}
                  end
                end

              binding ->
                {:ok, {query, binding}}
            end

          case query_and_binding do
            {:ok, {query, binding}} ->
              query_with_aggregate_binding =
                put_in(
                  query.__ash_bindings__.aggregates,
                  Map.put(query.__ash_bindings__.aggregates, aggregate.name, binding)
                )

              query_with_aggregate_defs =
                put_in(
                  query_with_aggregate_binding.__ash_bindings__.aggregate_defs,
                  Map.put(
                    query_with_aggregate_binding.__ash_bindings__.aggregate_defs,
                    aggregate.name,
                    aggregate
                  )
                )

              new_query =
                query_with_aggregate_defs
                |> add_aggregate_to_subquery(resource, aggregate, binding)

              if select? do
                dynamic = select_dynamic(resource, query, aggregate)
                {:cont, {:ok, new_query, [{aggregate.load, aggregate.name, dynamic} | dynamics]}}
              else
                {:cont, {:ok, new_query, dynamics}}
              end

            {:error, error} ->
              {:halt, {:error, error}}
          end
        end
      end)

    case result do
      {:ok, query, dynamics} ->
        {:ok, add_aggregate_selects(query, dynamics)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp add_aggregate_selects(query, dynamics) do
    {in_aggregates, in_body} =
      Enum.split_with(dynamics, fn {load, _name, _dynamic} -> is_nil(load) end)

    query =
      if query.select do
        query
      else
        Ecto.Query.select_merge(query, %{})
      end

    {exprs, new_params, count} =
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
          | expr: {:merge, [], [query.select.expr, {:%{}, [], Enum.reverse(exprs)}]}
        }
    }

    add_aggregates_in_aggregates(query, in_aggregates, new_params, count)
  end

  defp add_aggregates_in_aggregates(query, [], params, _count),
    do: %{query | select: %{query.select | params: Enum.reverse(params)}}

  defp add_aggregates_in_aggregates(
         %{select: %{expr: expr} = select} = query,
         in_aggregates,
         params,
         count
       ) do
    {exprs, new_params, _} =
      Enum.reduce(
        in_aggregates,
        {[], params, count},
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
          | expr: {:merge, [], [expr, {:%{}, [], [aggregates: {:%{}, [], Enum.reverse(exprs)}]}]},
            params: Enum.reverse(new_params)
        }
    }
  end

  def agg_subquery_for_lateral_join(current_binding, query, subquery, relationship) do
    {dest_binding, dest_field} =
      case relationship.type do
        :many_to_many ->
          {1, relationship.source_field_on_join_table}

        _ ->
          {0, relationship.destination_field}
      end

    inner_sub =
      from(destination in subquery,
        where:
          field(as(^dest_binding), ^dest_field) ==
            field(parent_as(^current_binding), ^relationship.source_field)
      )

    from(sub in subquery(inner_sub), [])
    |> AshPostgres.Join.set_join_prefix(query, relationship.destination)
  end

  defp select_dynamic(resource, query, aggregate) do
    binding =
      AshPostgres.DataLayer.get_binding(resource, aggregate.relationship_path, query, :aggregate)

    type = AshPostgres.Types.parameterized_type(aggregate.type, [])

    field =
      Ecto.Query.dynamic(
        type(
          field(as(^binding), ^aggregate.name),
          ^type
        )
      )

    coalesced =
      if is_nil(aggregate.default_value) do
        field
      else
        Ecto.Query.dynamic(
          coalesce(
            ^field,
            type(
              ^aggregate.default_value,
              ^type
            )
          )
        )
      end

    Ecto.Query.dynamic(type(^coalesced, ^type))
  end

  defp add_aggregate_to_subquery(query, resource, aggregate, binding) do
    new_joins =
      List.update_at(query.joins, binding - 1, fn join ->
        aggregate_query =
          if aggregate.authorization_filter do
            {:ok, filtered} =
              AshPostgres.DataLayer.filter(
                join.source.from.source.query,
                aggregate.authorization_filter,
                Ash.Resource.Info.related(resource, aggregate.relationship_path)
              )

            filtered
          else
            join.source.from.source.query
          end

        {:ok, aggregate_query} =
          AshPostgres.Aggregate.add_aggregates(
            aggregate_query,
            Map.values(aggregate.query.aggregates || %{}),
            Ash.Resource.Info.related(resource, aggregate.relationship_path),
            false
          )

        {:ok, aggregate_query} =
          if aggregate.query && aggregate.query.filter do
            AshPostgres.Join.join_all_relationships(
              aggregate_query,
              aggregate.query.filter,
              nil,
              [],
              nil,
              true
            )
          else
            {:ok, aggregate_query}
          end

        new_aggregate_query = add_subquery_aggregate_select(aggregate_query, aggregate, resource)

        put_in(join.source.from.source.query, new_aggregate_query)
      end)

    %{
      query
      | joins: new_joins
    }
  end

  def used_aggregates(filter, relationship, used_calculations, path) do
    Ash.Filter.used_aggregates(filter, path) ++
      Enum.flat_map(
        used_calculations,
        fn calculation ->
          case Ash.Filter.hydrate_refs(
                 calculation.module.expression(calculation.opts, calculation.context),
                 %{
                   resource: relationship.destination,
                   aggregates: %{},
                   calculations: %{},
                   public?: false
                 }
               ) do
            {:ok, hydrated} ->
              Ash.Filter.used_aggregates(hydrated)

            _ ->
              []
          end
        end
      )
  end

  def add_subquery_aggregate_select(query, %{kind: :first} = aggregate, _resource) do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)
    key = aggregate.field

    type = AshPostgres.Types.parameterized_type(aggregate.type, [])

    field =
      if aggregate.query && aggregate.query.sort && aggregate.query.sort != [] do
        sort_expr = AshPostgres.Sort.order_to_ecto(aggregate.query.sort)
        question_marks = Enum.map(sort_expr, fn _ -> " ? " end)
        field = Ecto.Query.dynamic([{^0, row}], field(row, ^key))

        {:ok, expr} =
          AshPostgres.Functions.Fragment.casted_new(
            ["array_agg(? ORDER BY #{question_marks})", field] ++ sort_expr
          )

        AshPostgres.Expr.dynamic_expr(query, expr, query.__ash_bindings__)
      else
        Ecto.Query.dynamic(
          [row],
          fragment("array_agg(?)", field(row, ^key))
        )
      end

    filtered =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
        expr =
          AshPostgres.Expr.dynamic_expr(
            query,
            aggregate.query.filter,
            query.__ash_bindings__
          )

        Ecto.Query.dynamic(filter(^field, ^expr))
      else
        field
      end

    value = Ecto.Query.dynamic(fragment("(?)[1]", ^filtered))

    with_default =
      if aggregate.default_value do
        Ecto.Query.dynamic(coalesce(^value, type(^aggregate.default_value, ^type)))
      else
        value
      end

    casted = Ecto.Query.dynamic(type(^with_default, ^type))

    select_or_merge(query, aggregate.name, casted)
  end

  def add_subquery_aggregate_select(query, %{kind: :list} = aggregate, _resource) do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)
    key = aggregate.field
    type = AshPostgres.Types.parameterized_type(aggregate.type, [])

    field =
      if aggregate.query && aggregate.query.sort && aggregate.query.sort != [] do
        sort_expr = AshPostgres.Sort.order_to_ecto(aggregate.query.sort)
        question_marks = Enum.map(sort_expr, fn _ -> " ? " end)
        field = Ecto.Query.dynamic([row], field(row, ^key))

        {:ok, expr} =
          AshPostgres.Functions.Fragment.casted_new(
            ["array_agg(? ORDER BY #{question_marks})", field] ++ sort_expr
          )

        AshPostgres.Expr.dynamic_expr(query, expr, query.__ash_bindings__)
      else
        Ecto.Query.dynamic(
          [row],
          fragment("array_agg(?)", field(row, ^key))
        )
      end

    filtered =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
        expr =
          AshPostgres.Expr.dynamic_expr(
            query,
            aggregate.query.filter,
            query.__ash_bindings__
          )

        Ecto.Query.dynamic(filter(^field, ^expr))
      else
        field
      end

    with_default =
      if aggregate.default_value do
        Ecto.Query.dynamic(coalesce(^filtered, type(^aggregate.default_value, ^type)))
      else
        filtered
      end

    cast = Ecto.Query.dynamic(type(^with_default, ^{:array, type}))

    select_or_merge(query, aggregate.name, cast)
  end

  def add_subquery_aggregate_select(query, %{kind: kind} = aggregate, resource)
      when kind in [:count, :sum] do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)
    key = aggregate.field || List.first(Ash.Resource.Info.primary_key(resource))
    type = AshPostgres.Types.parameterized_type(aggregate.type, [])

    field =
      case kind do
        :count ->
          Ecto.Query.dynamic([row], count(field(row, ^key)))

        :sum ->
          Ecto.Query.dynamic([row], sum(field(row, ^key)))
      end

    filtered =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
        expr =
          AshPostgres.Expr.dynamic_expr(
            query,
            aggregate.query.filter,
            query.__ash_bindings__
          )

        Ecto.Query.dynamic(filter(^field, ^expr))
      else
        field
      end

    with_default =
      if aggregate.default_value do
        Ecto.Query.dynamic(coalesce(^filtered, type(^aggregate.default_value, ^type)))
      else
        filtered
      end

    cast = Ecto.Query.dynamic(type(^with_default, ^type))

    select_or_merge(query, aggregate.name, cast)
  end

  defp select_or_merge(query, aggregate_name, casted) do
    query =
      if query.select do
        query
      else
        Ecto.Query.select(query, %{})
      end

    {expr, new_params, _} =
      Ecto.Query.Builder.Dynamic.partially_expand(
        :select,
        query,
        casted,
        Enum.reverse(query.select.params),
        Enum.count(query.select.params)
      )

    %{
      query
      | select: %{
          query.select
          | expr: {:merge, [], [query.select.expr, {:%{}, [], [{aggregate_name, expr}]}]},
            params: Enum.reverse(new_params)
        }
    }
  end

  defp aggregate_subquery(%{type: :many_to_many} = relationship, aggregate, root_query) do
    destination =
      case AshPostgres.Join.maybe_get_resource_query(
             relationship.destination,
             relationship,
             root_query
           ) do
        {:ok, query} ->
          query

        _ ->
          relationship.destination
      end

    join_relationship =
      Ash.Resource.Info.relationship(relationship.source, relationship.join_relationship)

    through =
      case AshPostgres.Join.maybe_get_resource_query(
             relationship.through,
             join_relationship,
             root_query
           ) do
        {:ok, query} ->
          query

        _ ->
          relationship.through
      end

    query =
      from(destination in destination,
        join: through in ^through,
        as: ^1,
        on:
          field(through, ^relationship.destination_field_on_join_table) ==
            field(destination, ^relationship.destination_field),
        group_by: field(through, ^relationship.source_field_on_join_table)
      )

    query_tenant = aggregate.query && aggregate.query.tenant
    root_tenant = root_query.prefix

    if Ash.Resource.Info.multitenancy_strategy(relationship.destination) &&
         (root_tenant ||
            query_tenant) do
      Ecto.Query.put_query_prefix(query, query_tenant || root_tenant)
    else
      %{
        query
        | prefix: AshPostgres.repo(relationship.destination).config()[:default_prefix] || "public"
      }
    end
  end

  defp aggregate_subquery(relationship, aggregate, root_query) do
    destination =
      case AshPostgres.Join.maybe_get_resource_query(
             relationship.destination,
             relationship,
             root_query
           ) do
        {:ok, query} ->
          query

        _ ->
          relationship.destination
      end

    query =
      from(row in destination,
        group_by: ^relationship.destination_field,
        select: %{}
      )

    query_tenant = aggregate.query && aggregate.query.tenant
    root_tenant = root_query.prefix

    if Ash.Resource.Info.multitenancy_strategy(relationship.destination) &&
         (root_tenant ||
            query_tenant) do
      Ecto.Query.put_query_prefix(query, query_tenant || root_tenant)
    else
      %{
        query
        | prefix: AshPostgres.repo(relationship.destination).config()[:default_prefix] || "public"
      }
    end
  end
end
