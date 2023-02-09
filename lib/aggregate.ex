defmodule AshPostgres.Aggregate do
  @moduledoc false

  import Ecto.Query, only: [from: 2, subquery: 1]
  require Ecto.Query

  def add_aggregates(query, aggregates, resource, select? \\ true, source_binding \\ nil)
  def add_aggregates(query, [], _, _, _), do: {:ok, query}

  def add_aggregates(query, aggregates, resource, select?, source_binding) do
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

    source_binding =
      source_binding ||
        query.__ash_bindings__.bindings
        |> Enum.reject(fn
          {_, %{aggregates: _}} ->
            true

          _ ->
            false
        end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.max()

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

        first_can_join? =
          case aggregates do
            [aggregate] ->
              single_path?(resource, aggregate.relationship_path)

            _ ->
              false
          end

        if first_can_join? do
          case add_first_join_aggregate(query, resource, hd(aggregates)) do
            {:ok, query, dynamic} ->
              query =
                if select? do
                  select_or_merge(query, hd(aggregates).name, dynamic)
                else
                  query
                end

              {:cont, {:ok, query, dynamics}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
        else
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
                   is_single?,
                   source_binding
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
        end
      end)

    case result do
      {:ok, query, dynamics} ->
        {:ok, add_aggregate_selects(query, dynamics)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp add_first_join_aggregate(query, resource, aggregate) do
    parent_path =
      case query.__ash_bindings__ do
        %{parent_paths: [{path, parent_resource}]} ->
          AshPostgres.Join.relationship_path_to_relationships(
            parent_resource,
            path
          )

        _ ->
          []
      end

    case AshPostgres.Join.join_all_relationships(
           query,
           nil,
           [],
           [
             {:left,
              AshPostgres.Join.relationship_path_to_relationships(
                resource,
                aggregate.relationship_path
              )}
           ],
           parent_path,
           nil
         ) do
      {:ok, query} ->
        binding =
          AshPostgres.DataLayer.get_binding(
            resource,
            aggregate.relationship_path,
            query,
            [:left, :inner]
          )

        {:ok, query, Ecto.Query.dynamic(field(as(^binding), ^aggregate.field))}

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
         _first_relationship,
         _relationship_path,
         [_aggregate | _rest],
         false,
         _source_binding
       ) do
    {:ok, agg_query}
  end

  defp maybe_filter_subquery(
         agg_query,
         first_relationship,
         relationship_path,
         [aggregate],
         true,
         source_binding
       ) do
    apply_agg_query(
      agg_query,
      aggregate,
      relationship_path,
      first_relationship,
      source_binding
    )
  end

  defp apply_agg_query(
         agg_query,
         aggregate,
         relationship_path,
         first_relationship,
         source_binding
       ) do
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

      related = Ash.Resource.Info.related(first_relationship.destination, relationship_path)

      used_calculations =
        case Ash.Resource.Info.calculation(related, aggregate.field) do
          %{name: name, calculation: {module, opts}, type: type, constraints: constraints} ->
            {:ok, new_calc} = Ash.Query.Calculation.new(name, module, opts, {type, constraints})

            if new_calc in used_calculations do
              used_calculations
            else
              [
                new_calc
                | used_calculations
              ]
            end

          nil ->
            used_calculations
        end

      used_aggregates =
        used_aggregates(
          filter,
          first_relationship.destination,
          used_calculations,
          relationship_path
        )

      case add_aggregates(
             agg_query,
             used_aggregates,
             first_relationship.destination,
             false,
             source_binding
           ) do
        {:ok, agg_query} ->
          AshPostgres.DataLayer.filter(agg_query, filter, agg_query.__ash_bindings__.resource)

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
        left_lateral_join: sub in subquery(subquery_if_distinct(subquery)),
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
        left_lateral_join: agg in subquery(subquery_if_distinct(subquery)),
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
        left_lateral_join: agg in subquery(subquery_if_distinct(subquery)),
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

  defp subquery_if_distinct(%{distinct: nil} = query), do: query

  defp subquery_if_distinct(subquery) do
    from(row in subquery(subquery),
      select: row
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
        [],
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
      if array_type?(resource, aggregate) || single_path?(resource, aggregate.relationship_path) do
        false
      else
        true
      end
    else
      true
    end
  end

  defp array_type?(resource, aggregate) do
    related = Ash.Resource.Info.related(resource, aggregate.relationship_path)

    case Ash.Resource.Info.field(related, aggregate.field).type do
      {:array, _} ->
        false

      _ ->
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

    ref = %Ash.Query.Ref{
      attribute: Ash.Resource.Info.field(resource, aggregate.field),
      relationship_path: relationship_path,
      resource: query.__ash_bindings__.resource
    }

    type = AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)

    binding =
      AshPostgres.DataLayer.get_binding(
        query.__ash_bindings__.resource,
        relationship_path,
        query,
        [:left, :inner, :root]
      )

    field = AshPostgres.Expr.dynamic_expr(query, ref, query.__ash_bindings__, false)

    sorted =
      if has_sort?(aggregate.query) do
        {:ok, sort_expr} =
          AshPostgres.Sort.sort(
            query,
            aggregate.query.sort,
            Ash.Resource.Info.related(
              query.__ash_bindings__.resource,
              relationship_path
            ),
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

    value = Ecto.Query.dynamic(fragment("(?)[1]", ^filtered))

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
    type = AshPostgres.Types.parameterized_type(aggregate.type, aggregate.constraints)

    binding =
      AshPostgres.DataLayer.get_binding(
        query.__ash_bindings__.resource,
        relationship_path,
        query,
        [:left, :inner, :root]
      )

    ref = %Ash.Query.Ref{
      attribute: Ash.Resource.Info.field(resource, aggregate.field),
      relationship_path: relationship_path,
      resource: query.__ash_bindings__.resource
    }

    field = AshPostgres.Expr.dynamic_expr(query, ref, query.__ash_bindings__, false)

    sorted =
      if has_sort?(aggregate.query) do
        {:ok, sort_expr} =
          AshPostgres.Sort.sort(
            query,
            aggregate.query.sort,
            Ash.Resource.Info.related(
              query.__ash_bindings__.resource,
              relationship_path
            ),
            relationship_path,
            binding,
            true
          )

        question_marks = Enum.map(sort_expr, fn _ -> " ? " end)

        distinct =
          if Map.get(aggregate, :uniq?) do
            "DISTINCT "
          else
            ""
          end

        {:ok, expr} =
          AshPostgres.Functions.Fragment.casted_new(
            ["array_agg(#{distinct}? ORDER BY #{question_marks})", field] ++ sort_expr
          )

        AshPostgres.Expr.dynamic_expr(query, expr, query.__ash_bindings__, false)
      else
        if Map.get(aggregate, :uniq?) do
          Ecto.Query.dynamic(
            [row],
            fragment("array_agg(DISTINCT ?)", ^field)
          )
        else
          Ecto.Query.dynamic(
            [row],
            fragment("array_agg(?)", ^field)
          )
        end
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

    ref = %Ash.Query.Ref{
      attribute:
        Ash.Resource.Info.field(
          resource,
          aggregate.field || List.first(Ash.Resource.Info.primary_key(resource))
        ),
      relationship_path: relationship_path,
      resource: resource
    }

    field =
      if kind == :custom do
        # we won't use this if its custom so don't try to make one
        nil
      else
        AshPostgres.Expr.dynamic_expr(query, ref, query.__ash_bindings__, false)
      end

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
          if Map.get(aggregate, :uniq?) do
            Ecto.Query.dynamic([row], count(^field, :distinct))
          else
            Ecto.Query.dynamic([row], count(^field, :distinct))
          end

        :sum ->
          Ecto.Query.dynamic([row], sum(^field))

        :avg ->
          Ecto.Query.dynamic([row], avg(^field))

        :max ->
          Ecto.Query.dynamic([row], max(^field))

        :min ->
          Ecto.Query.dynamic([row], min(^field))

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

  @doc false
  def single_path?(_, []), do: true

  def single_path?(resource, [relationship | rest]) do
    relationship = Ash.Resource.Info.relationship(resource, relationship)
    relationship.type == :belongs_to && single_path?(relationship.destination, rest)
  end
end
