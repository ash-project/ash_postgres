defmodule AshPostgres.Aggregate do
  @moduledoc false

  import Ecto.Query, only: [from: 2, subquery: 1]
  require Ecto.Query

  def add_aggregates(query, aggregates, resource, select? \\ true)
  def add_aggregates(query, [], _, _), do: {:ok, query}

  def add_aggregates(query, aggregates, resource, select?) do
    query = AshPostgres.DataLayer.default_bindings(query, resource)

    aggregates =
      Enum.reject(aggregates, fn aggregate ->
        Map.has_key?(query.__ash_bindings__.aggregate_defs, aggregate.name)
      end)

    query =
      query
      |> Map.update!(:__ash_bindings__, fn bindings ->
        bindings
        |> Map.update!(:aggregate_defs, fn aggregate_defs ->
          Map.merge(aggregate_defs, Map.new(aggregates, &{&1.name, &1}))
        end)
      end)

    source_binding = query.__ash_bindings__.current - 1

    result =
      aggregates
      |> Enum.reject(&already_added?(&1, query.__ash_bindings__))
      |> Enum.group_by(& &1.relationship_path)
      |> Enum.flat_map(fn {path, aggregates} ->
        {can_group, cant_group} = Enum.split_with(aggregates, &can_group?(resource, &1))

        [{path, can_group}] ++ Enum.map(cant_group, &{path, [&1]})
      end)
      |> Enum.filter(fn
        {_, []} ->
          false

        _ ->
          true
      end)
      |> Enum.reduce_while({:ok, query, []}, fn {[first_relationship | relationship_path],
                                                 aggregates},
                                                {:ok, query, dynamics} ->
        first_relationship = Ash.Resource.Info.relationship(resource, first_relationship)
        is_single? = Enum.count_until(aggregates, 2) == 1

        with {:ok, agg_root_query} <-
               AshPostgres.Join.maybe_get_resource_query(
                 first_relationship.destination,
                 first_relationship,
                 query
               ),
             agg_root_query <-
               Map.update!(agg_root_query, :__ash_bindings__, &Map.put(&1, :in_group?, true)),
             {:ok, joined} <-
               join_all_relationships(
                 agg_root_query,
                 aggregates,
                 relationship_path,
                 first_relationship,
                 is_single?
               ),
             {:ok, filtered} <-
               maybe_filter_subquery(
                 joined,
                 first_relationship,
                 relationship_path,
                 aggregates,
                 is_single?
               ),
             with_subquery_select <-
               select_all_aggregates(
                 aggregates,
                 filtered,
                 relationship_path,
                 query,
                 is_single?,
                 Ash.Resource.Info.related(first_relationship.destination, relationship_path)
               ),
             query <-
               join_subquery(
                 query,
                 with_subquery_select,
                 first_relationship,
                 relationship_path,
                 aggregates,
                 source_binding
               ) do
          if select? do
            new_dynamics =
              Enum.map(
                aggregates,
                &{&1.load, &1.name,
                 select_dynamic(resource, query, &1, query.__ash_bindings__.current - 1)}
              )

            {:cont, {:ok, query, new_dynamics ++ dynamics}}
          else
            {:cont, {:ok, query, dynamics}}
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

  defp already_added?(aggregate, bindings) do
    Enum.any?(bindings.bindings, fn
      {_, %{type: :aggregate, aggregates: aggregates}} ->
        aggregate in aggregates

      _ ->
        false
    end)
  end

  defp maybe_filter_subquery(
         agg_query,
         first_relationship,
         relationship_path,
         [aggregate | _rest],
         false
       ) do
    apply_agg_authorization_filter(agg_query, aggregate, relationship_path, first_relationship)
  end

  defp maybe_filter_subquery(agg_query, first_relationship, relationship_path, [aggregate], true) do
    with {:ok, agg_query} <-
           apply_agg_query(
             agg_query,
             aggregate,
             relationship_path,
             first_relationship
           ) do
      apply_agg_authorization_filter(
        agg_query,
        aggregate,
        relationship_path,
        first_relationship
      )
    end
  end

  defp apply_agg_query(agg_query, aggregate, relationship_path, first_relationship) do
    if has_filter?(aggregate.query) do
      filter =
        Ash.Filter.move_to_relationship_path(
          aggregate.query.filter,
          relationship_path
        )
        |> Map.put(:resource, first_relationship.destination)

      used_calculations =
        Ash.Filter.used_calculations(
          filter,
          first_relationship.destination,
          relationship_path
        )

      used_aggregates =
        used_aggregates(
          filter,
          first_relationship.destination,
          used_calculations,
          relationship_path
        )

      case add_aggregates(agg_query, used_aggregates, first_relationship.destination, false) do
        {:ok, agg_query} ->
          AshPostgres.DataLayer.filter(agg_query, filter, first_relationship.destination)

        other ->
          other
      end
    else
      {:ok, agg_query}
    end
  end

  defp apply_agg_authorization_filter(agg_query, aggregate, relationship_path, first_relationship) do
    if aggregate.authorization_filter do
      filter =
        Ash.Filter.move_to_relationship_path(
          aggregate.query.filter,
          relationship_path
        )
        |> Map.put(:resource, first_relationship.destination)

      used_calculations =
        Ash.Filter.used_calculations(
          filter,
          first_relationship.destination,
          relationship_path
        )

      used_aggregates =
        used_aggregates(
          filter,
          first_relationship.destination,
          used_calculations,
          relationship_path
        )

      case add_aggregates(agg_query, used_aggregates, first_relationship.destination, false) do
        {:ok, agg_query} ->
          AshPostgres.DataLayer.filter(agg_query, filter, first_relationship.destination)

        other ->
          other
      end
    else
      {:ok, agg_query}
    end
  end

  defp join_subquery(
         query,
         subquery,
         %{manual: {module, opts}} = first_relationship,
         _relationship_path,
         aggregates,
         source_binding
       ) do
    field = first_relationship.destination_attribute

    new_subquery =
      from(row in subquery,
        select_merge: map(row, ^[field]),
        group_by: field(row, ^first_relationship.destination_attribute),
        distinct: true
      )

    {:ok, subquery} =
      module.ash_postgres_subquery(
        opts,
        source_binding,
        subquery.__ash_bindings__.current - 1,
        new_subquery
      )

    subquery = AshPostgres.Join.set_join_prefix(subquery, query, first_relationship.destination)

    query =
      from(row in query,
        left_lateral_join: sub in subquery(subquery),
        as: ^query.__ash_bindings__.current
      )

    AshPostgres.DataLayer.add_binding(
      query,
      %{
        path: [],
        type: :aggregate,
        aggregates: aggregates
      }
    )
  end

  defp join_subquery(
         query,
         subquery,
         %{type: :many_to_many, join_relationship: join_relationship, source: source} =
           first_relationship,
         _relationship_path,
         aggregates,
         source_binding
       ) do
    join_relationship_struct = Ash.Resource.Info.relationship(source, join_relationship)

    {:ok, through} =
      AshPostgres.Join.maybe_get_resource_query(
        join_relationship_struct.destination,
        join_relationship_struct,
        query,
        [],
        nil,
        subquery.__ash_bindings__.current
      )

    field = first_relationship.source_attribute_on_join_resource

    subquery =
      from(sub in subquery,
        join: through in ^through,
        as: ^subquery.__ash_bindings__.current,
        on:
          field(through, ^first_relationship.destination_attribute_on_join_resource) ==
            field(sub, ^first_relationship.destination_attribute),
        select_merge: map(through, ^[field]),
        group_by: field(through, ^first_relationship.source_attribute_on_join_resource),
        distinct: field(through, ^first_relationship.source_attribute_on_join_resource),
        where:
          field(
            parent_as(^source_binding),
            ^first_relationship.source_attribute
          ) ==
            field(
              through,
              ^first_relationship.source_attribute_on_join_resource
            )
      )

    subquery = AshPostgres.Join.set_join_prefix(subquery, query, first_relationship.destination)

    query =
      from(row in query,
        left_lateral_join: agg in subquery(subquery),
        as: ^query.__ash_bindings__.current
      )

    AshPostgres.DataLayer.add_binding(
      query,
      %{
        path: [],
        type: :aggregate,
        aggregates: aggregates
      }
    )
  end

  defp join_subquery(
         query,
         subquery,
         first_relationship,
         _relationship_path,
         aggregates,
         source_binding
       ) do
    field = first_relationship.destination_attribute

    subquery =
      from(row in subquery,
        group_by: field(row, ^first_relationship.destination_attribute),
        select_merge: map(row, ^[field]),
        where:
          field(parent_as(^source_binding), ^first_relationship.source_attribute) ==
            field(as(^0), ^first_relationship.destination_attribute)
      )

    subquery = AshPostgres.Join.set_join_prefix(subquery, query, first_relationship.destination)

    query =
      from(row in query,
        left_lateral_join: agg in subquery(subquery),
        as: ^query.__ash_bindings__.current
      )

    AshPostgres.DataLayer.add_binding(
      query,
      %{
        path: [],
        type: :aggregate,
        aggregates: aggregates
      }
    )
  end

  defp select_all_aggregates(aggregates, joined, relationship_path, _query, is_single?, resource) do
    Enum.reduce(aggregates, joined, fn aggregate, joined ->
      add_subquery_aggregate_select(joined, relationship_path, aggregate, resource, is_single?)
    end)
  end

  defp join_all_relationships(
         agg_root_query,
         _aggregates,
         relationship_path,
         first_relationship,
         _is_single?
       ) do
    if Enum.empty?(relationship_path) do
      {:ok, agg_root_query}
    else
      AshPostgres.Join.join_all_relationships(
        agg_root_query,
        nil,
        [
          {:inner,
           AshPostgres.Join.relationship_path_to_relationships(
             first_relationship.destination,
             relationship_path
           )}
        ],
        [],
        nil
      )
    end
  end

  defp can_group?(_, %{kind: :list}), do: false

  defp can_group?(resource, aggregate) do
    can_group_kind?(aggregate, resource) && !has_exists?(aggregate) &&
      !references_relationships?(aggregate)
  end

  # We can potentially optimize this. We don't have to prevent aggregates that reference
  # relationships from joining, we can
  # 1. group up the ones that do join relationships by the relationships they join
  # 2. potentially group them all up that join to relationships and just join to all the relationships
  # but this method is predictable and easy so we're starting by just not grouping them
  defp references_relationships?(aggregate) do
    !!Ash.Filter.find(aggregate.query && aggregate.query.filter, fn
      %Ash.Query.Ref{relationship_path: relationship_path} when relationship_path != [] ->
        true

      _ ->
        false
    end)
  end

  defp can_group_kind?(aggregate, resource) do
    if aggregate.kind == :first do
      related = Ash.Resource.Info.related(resource, aggregate.relationship_path)

      case Ash.Resource.Info.attribute(related, aggregate.field).type do
        {:array, _} ->
          false

        _ ->
          true
      end
    else
      true
    end
  end

  defp has_exists?(aggregate) do
    !!Ash.Filter.find(aggregate.query && aggregate.query.filter, fn
      %Ash.Query.Exists{} -> true
      _ -> false
    end)
  end

  defp add_aggregate_selects(query, dynamics) do
    {in_aggregates, in_body} =
      Enum.split_with(dynamics, fn {load, _name, _dynamic} -> is_nil(load) end)

    aggs =
      in_body
      |> Map.new(fn {load, _, dynamic} ->
        {load, dynamic}
      end)

    aggs =
      if Enum.empty?(in_aggregates) do
        aggs
      else
        Map.put(
          aggs,
          :aggregates,
          Map.new(in_aggregates, fn {_, name, dynamic} ->
            {name, dynamic}
          end)
        )
      end

    Ecto.Query.select_merge(query, ^aggs)
  end

  def agg_subquery_for_lateral_join(
        current_binding,
        query,
        subquery,
        %{
          manual: {module, opts}
        } = relationship
      ) do
    case module.ash_postgres_subquery(
           opts,
           current_binding,
           0,
           subquery
         ) do
      {:ok, inner_sub} ->
        {:ok,
         from(sub in subquery(inner_sub), [])
         |> AshPostgres.Join.set_join_prefix(query, relationship.destination)}

      other ->
        other
    end
  rescue
    e in UndefinedFunctionError ->
      if e.function == :ash_postgres_subquery do
        reraise """
                Cannot join to a manual relationship #{inspect(module)} that does not implement the `AshPostgres.ManualRelationship` behaviour.
                """,
                __STACKTRACE__
      else
        reraise e, __STACKTRACE__
      end
  end

  def agg_subquery_for_lateral_join(current_binding, query, subquery, relationship) do
    {dest_binding, dest_field} =
      case relationship.type do
        :many_to_many ->
          {1, relationship.source_attribute_on_join_resource}

        _ ->
          {0, relationship.destination_attribute}
      end

    inner_sub =
      if Map.get(relationship, :no_attributes?) do
        subquery
      else
        from(destination in subquery,
          where:
            field(as(^dest_binding), ^dest_field) ==
              field(parent_as(^current_binding), ^relationship.source_attribute)
        )
      end

    {:ok,
     from(sub in subquery(inner_sub), [])
     |> AshPostgres.Join.set_join_prefix(query, relationship.destination)}
  end

  defp select_dynamic(_resource, _query, aggregate, binding) do
    type = AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)

    field =
      if type do
        Ecto.Query.dynamic(
          type(
            field(as(^binding), ^aggregate.name),
            ^type
          )
        )
      else
        Ecto.Query.dynamic(field(as(^binding), ^aggregate.name))
      end

    coalesced =
      if is_nil(aggregate.default_value) do
        field
      else
        if type do
          Ecto.Query.dynamic(
            coalesce(
              ^field,
              type(
                ^aggregate.default_value,
                ^type
              )
            )
          )
        else
          Ecto.Query.dynamic(
            coalesce(
              ^field,
              ^aggregate.default_value
            )
          )
        end
      end

    if type do
      Ecto.Query.dynamic(type(^coalesced, ^type))
    else
      coalesced
    end
  end

  defp has_filter?(nil), do: false
  defp has_filter?(%{filter: nil}), do: false
  defp has_filter?(%{filter: %Ash.Filter{expression: nil}}), do: false
  defp has_filter?(%{filter: %Ash.Filter{}}), do: true
  defp has_filter?(_), do: false

  defp has_sort?(nil), do: false
  defp has_sort?(%{sort: nil}), do: false
  defp has_sort?(%{sort: []}), do: false
  defp has_sort?(%{sort: _}), do: true
  defp has_sort?(_), do: false

  def used_aggregates(filter, resource, used_calculations, path) do
    Ash.Filter.used_aggregates(filter, path) ++
      Enum.flat_map(
        used_calculations,
        fn calculation ->
          case Ash.Filter.hydrate_refs(
                 calculation.module.expression(calculation.opts, calculation.context),
                 %{
                   resource: resource,
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

  def add_subquery_aggregate_select(
        query,
        relationship_path,
        %{kind: :first} = aggregate,
        resource,
        is_single?
      ) do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)
    key = aggregate.field

    type = AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)

    binding =
      AshPostgres.DataLayer.get_binding(
        query.__ash_bindings__.resource,
        relationship_path,
        query,
        [:left, :inner, :root]
      )

    field =
      Ecto.Query.dynamic(
        [row],
        field(as(^binding), ^key)
      )

    sorted =
      if has_sort?(aggregate.query) do
        {:ok, sort_expr} =
          AshPostgres.Sort.sort(
            query,
            aggregate.query.sort,
            Ash.Resource.Info.related(resource, relationship_path),
            relationship_path,
            binding,
            true
          )

        question_marks = Enum.map(sort_expr, fn _ -> " ? " end)

        {:ok, expr} =
          AshPostgres.Functions.Fragment.casted_new(
            ["array_agg(? ORDER BY #{question_marks})", field] ++ sort_expr
          )

        AshPostgres.Expr.dynamic_expr(query, expr, query.__ash_bindings__, false)
      else
        Ecto.Query.dynamic(
          [row],
          fragment("array_agg(?)", ^field)
        )
      end

    filtered = filter_field(sorted, query, aggregate, relationship_path, is_single?)

    value = Ecto.Query.dynamic([], fragment("(?)[1]", ^filtered))

    with_default =
      if aggregate.default_value do
        if type do
          Ecto.Query.dynamic(coalesce(^value, type(^aggregate.default_value, ^type)))
        else
          Ecto.Query.dynamic(coalesce(^value, ^aggregate.default_value))
        end
      else
        value
      end

    casted =
      if type do
        Ecto.Query.dynamic(type(^with_default, ^type))
      else
        with_default
      end

    select_or_merge(query, aggregate.name, casted)
  end

  def add_subquery_aggregate_select(
        query,
        relationship_path,
        %{kind: :list} = aggregate,
        resource,
        is_single?
      ) do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)
    key = aggregate.field
    type = AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)

    binding =
      AshPostgres.DataLayer.get_binding(
        query.__ash_bindings__.resource,
        relationship_path,
        query,
        [:left, :inner, :root]
      )

    field =
      Ecto.Query.dynamic(
        [row],
        field(as(^binding), ^key)
      )

    sorted =
      if has_sort?(aggregate.query) do
        {:ok, sort_expr} =
          AshPostgres.Sort.sort(
            query,
            aggregate.query.sort,
            Ash.Resource.Info.related(resource, relationship_path),
            relationship_path,
            binding,
            true
          )

        question_marks = Enum.map(sort_expr, fn _ -> " ? " end)

        {:ok, expr} =
          AshPostgres.Functions.Fragment.casted_new(
            ["array_agg(? ORDER BY #{question_marks})", field] ++ sort_expr
          )

        AshPostgres.Expr.dynamic_expr(query, expr, query.__ash_bindings__, false)
      else
        Ecto.Query.dynamic(
          [row],
          fragment("array_agg(?)", ^field)
        )
      end

    filtered = filter_field(sorted, query, aggregate, relationship_path, is_single?)

    with_default =
      if aggregate.default_value do
        if type do
          Ecto.Query.dynamic(coalesce(^filtered, type(^aggregate.default_value, ^type)))
        else
          Ecto.Query.dynamic(coalesce(^filtered, ^aggregate.default_value))
        end
      else
        filtered
      end

    cast =
      if type do
        Ecto.Query.dynamic(type(^with_default, ^{:array, type}))
      else
        with_default
      end

    select_or_merge(query, aggregate.name, cast)
  end

  def add_subquery_aggregate_select(
        query,
        relationship_path,
        %{kind: kind} = aggregate,
        resource,
        is_single?
      )
      when kind in [:count, :sum, :avg, :max, :min, :custom] do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)
    key = aggregate.field || List.first(Ash.Resource.Info.primary_key(resource))
    type = AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)

    binding =
      AshPostgres.DataLayer.get_binding(
        query.__ash_bindings__.resource,
        relationship_path,
        query,
        [:left, :inner, :root]
      )

    field =
      case kind do
        :count ->
          Ecto.Query.dynamic([row], count(field(as(^binding), ^key)))

        :sum ->
          Ecto.Query.dynamic([row], sum(field(as(^binding), ^key)))

        :avg ->
          Ecto.Query.dynamic([row], avg(field(as(^binding), ^key)))

        :max ->
          Ecto.Query.dynamic([row], max(field(as(^binding), ^key)))

        :min ->
          Ecto.Query.dynamic([row], min(field(as(^binding), ^key)))

        :custom ->
          {module, opts} = aggregate.implementation

          module.dynamic(opts, binding)
      end

    filtered = filter_field(field, query, aggregate, relationship_path, is_single?)

    with_default =
      if aggregate.default_value do
        if type do
          Ecto.Query.dynamic(coalesce(^filtered, type(^aggregate.default_value, ^type)))
        else
          Ecto.Query.dynamic(coalesce(^filtered, ^aggregate.default_value))
        end
      else
        filtered
      end

    cast =
      if type do
        Ecto.Query.dynamic(type(^with_default, ^type))
      else
        with_default
      end

    select_or_merge(query, aggregate.name, cast)
  end

  defp filter_field(field, _query, _aggregate, _relationship_path, true) do
    field
  end

  defp filter_field(field, query, aggregate, relationship_path, _is_single?) do
    if has_filter?(aggregate.query) do
      filter =
        Ash.Filter.move_to_relationship_path(
          aggregate.query.filter,
          relationship_path
        )

      expr =
        AshPostgres.Expr.dynamic_expr(
          query,
          filter,
          query.__ash_bindings__,
          false,
          AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)
        )

      Ecto.Query.dynamic(filter(^field, ^expr))
    else
      field
    end
  end

  defp select_or_merge(query, aggregate_name, casted) do
    query =
      if query.select do
        query
      else
        Ecto.Query.select(query, %{})
      end

    Ecto.Query.select_merge(query, ^%{aggregate_name => casted})
  end
end
