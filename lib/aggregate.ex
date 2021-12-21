defmodule AshPostgres.Aggregate do
  @moduledoc false

  import Ecto.Query, only: [from: 2, subquery: 1]
  require Ecto.Query

  def add_aggregate(query, aggregate, _resource, add_base? \\ true) do
    resource = aggregate.resource
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    query_and_binding =
      case AshPostgres.DataLayer.get_binding(
             resource,
             aggregate.relationship_path,
             query,
             :aggregate
           ) do
        nil ->
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)

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
          |> select_aggregate(resource, aggregate, add_base?)

        {:ok, new_query}

      {:error, error} ->
        {:error, error}
    end
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

    from(
      sub in subquery(inner_sub),
      select: field(as(^dest_binding), ^dest_field)
    )
    |> AshPostgres.Join.set_join_prefix(query, relationship.destination)
  end

  defp select_aggregate(query, resource, aggregate, add_base?) do
    binding =
      AshPostgres.DataLayer.get_binding(resource, aggregate.relationship_path, query, :aggregate)

    query =
      if query.select do
        query
      else
        if add_base? do
          from(row in query,
            select: row,
            select_merge: %{aggregates: %{}, calculations: %{}}
          )
        else
          from(row in query, select: row)
        end
      end

    %{query | select: add_to_aggregate_select(query.select, binding, aggregate)}
  end

  defp add_to_aggregate_select(
         %{
           expr:
             {:merge, _,
              [
                first,
                {:%{}, _,
                 [{:aggregates, {:%{}, [], fields}}, {:calculations, {:%{}, [], calc_fields}}]}
              ]}
         } = select,
         binding,
         %{load: nil} = aggregate
       ) do
    field =
      Ecto.Query.dynamic(
        type(
          field(as(^binding), ^aggregate.name),
          ^AshPostgres.Types.parameterized_type(aggregate.type, [])
        )
      )

    field_with_default =
      if is_nil(aggregate.default_value) do
        field
      else
        Ecto.Query.dynamic(
          coalesce(
            ^field,
            type(
              ^aggregate.default_value,
              ^AshPostgres.Types.parameterized_type(aggregate.type, [])
            )
          )
        )
      end

    new_fields = [
      {aggregate.name, field_with_default}
      | fields
    ]

    %{
      select
      | expr:
          {:merge, [],
           [
             first,
             {:%{}, [],
              [{:aggregates, {:%{}, [], new_fields}}, {:calculations, {:%{}, [], calc_fields}}]}
           ]}
    }
  end

  defp add_to_aggregate_select(
         %{expr: expr} = select,
         binding,
         %{load: load_as} = aggregate
       ) do
    field =
      Ecto.Query.dynamic(
        type(
          field(as(^binding), ^aggregate.name),
          ^AshPostgres.Types.parameterized_type(aggregate.type, [])
        )
      )

    field_with_default =
      if is_nil(aggregate.default_value) do
        field
      else
        Ecto.Query.dynamic(
          coalesce(
            ^field,
            type(
              ^aggregate.default_value,
              ^AshPostgres.Types.parameterized_type(aggregate.type, [])
            )
          )
        )
      end

    %{select | expr: {:merge, [], [expr, {:%{}, [], [{load_as, field_with_default}]}]}}
  end

  defp add_aggregate_to_subquery(query, resource, aggregate, binding) do
    new_joins =
      List.update_at(query.joins, binding - 1, fn join ->
        aggregate_query =
          if aggregate.authorization_filter do
            {:ok, filter} =
              AshPostgres.DataLayer.filter(
                join.source.from.source.query,
                aggregate.authorization_filter,
                Ash.Resource.Info.related(resource, aggregate.relationship_path)
              )

            filter
          else
            join.source.from.source.query
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
    Ash.Filter.used_aggregates(filter, path ++ [relationship.name]) ++
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
        sort_expr =
          aggregate.query.sort
          |> Enum.map(fn {sort, order} ->
            case AshPostgres.Sort.order_to_postgres_order(order) do
              nil ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}]

              order ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}, raw: order]
            end
          end)
          |> Enum.intersperse(raw: ", ")
          |> List.flatten()

        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: " ORDER BY "
         ] ++
           close_paren(sort_expr)}
      else
        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: ")"
         ]}
      end

    field = %Ecto.Query.DynamicExpr{
      fun: fn _query ->
        {field, [], []}
      end,
      binding: [],
      file: __ENV__.file,
      line: __ENV__.line
    }

    filtered =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
        expr =
          AshPostgres.Expr.dynamic_expr(
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

    new_expr = {:merge, [], [query.select.expr, {:%{}, [], [{aggregate.name, casted}]}]}

    %{query | select: %{query.select | expr: new_expr}}
  end

  def add_subquery_aggregate_select(query, %{kind: :list} = aggregate, _resource) do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)
    key = aggregate.field
    type = AshPostgres.Types.parameterized_type(aggregate.type, [])

    field =
      if aggregate.query && aggregate.query.sort && aggregate.query.sort != [] do
        sort_expr =
          aggregate.query.sort
          |> Enum.map(fn {sort, order} ->
            case AshPostgres.Sort.order_to_postgres_order(order) do
              nil ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}]

              order ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}, raw: order]
            end
          end)
          |> Enum.intersperse(raw: ", ")
          |> List.flatten()

        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: " ORDER BY "
         ] ++
           close_paren(sort_expr)}
      else
        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: ")"
         ]}
      end

    field = %Ecto.Query.DynamicExpr{
      fun: fn _query ->
        {field, [], []}
      end,
      binding: [],
      file: __ENV__.file,
      line: __ENV__.line
    }

    filtered =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
        expr =
          AshPostgres.Expr.dynamic_expr(
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

    new_expr = {:merge, [], [query.select.expr, {:%{}, [], [{aggregate.name, cast}]}]}

    %{query | select: %{query.select | expr: new_expr}}
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

    new_expr = {:merge, [], [query.select.expr, {:%{}, [], [{aggregate.name, cast}]}]}

    %{query | select: %{query.select | expr: new_expr}}
  end

  defp close_paren(list) do
    count = length(list)

    case List.last(list) do
      {:raw, _} ->
        List.update_at(list, count - 1, fn {:raw, str} ->
          {:raw, str <> ")"}
        end)

      _ ->
        list ++ [{:raw, ")"}]
    end
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
        on:
          field(through, ^relationship.destination_field_on_join_table) ==
            field(destination, ^relationship.destination_field),
        group_by: field(through, ^relationship.source_field_on_join_table),
        select: %{__source_field: field(through, ^relationship.source_field_on_join_table)}
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
        select: field(row, ^relationship.destination_field)
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
