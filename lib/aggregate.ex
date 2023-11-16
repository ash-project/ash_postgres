defmodule AshPostgres.Aggregate do
  @moduledoc false

  import Ecto.Query, only: [from: 2, subquery: 1]
  require Ecto.Query

  @next_aggregate_names Enum.reduce(0..999, %{}, fn i, acc ->
                          Map.put(acc, :"aggregate_#{i}", :"aggregate_#{i + 1}")
                        end)

  def add_aggregates(
        query,
        aggregates,
        resource,
        select?,
        source_binding,
        root_data \\ nil
      )

  def add_aggregates(query, [], _, _, _, _), do: {:ok, query}

  def add_aggregates(query, aggregates, resource, select?, source_binding, root_data) do
    case resource_aggregates_to_aggregates(resource, aggregates) do
      {:ok, aggregates} ->
        query = AshPostgres.DataLayer.default_bindings(query, resource)

        {query, aggregates, aggregate_name_mapping} =
          Enum.reduce(aggregates, {query, [], %{}}, fn aggregate,
                                                       {query, aggregates, aggregate_name_mapping} ->
            if is_atom(aggregate.name) do
              {query, [aggregate | aggregates], aggregate_name_mapping}
            else
              {query, name} = use_aggregate_name(query, aggregate.name)

              {query, [%{aggregate | name: name} | aggregates],
               Map.put(aggregate_name_mapping, name, aggregate.name)}
            end
          end)

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
          |> Enum.reduce_while(
            {:ok, query, []},
            fn {[first_relationship | relationship_path], aggregates}, {:ok, query, dynamics} ->
              first_relationship = Ash.Resource.Info.relationship(resource, first_relationship)
              is_single? = match?([_], aggregates)

              cond do
                is_single? &&
                    optimizable_first_aggregate?(resource, Enum.at(aggregates, 0)) ->
                  case add_first_join_aggregate(query, resource, hd(aggregates), root_data) do
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

                is_single? && Enum.at(aggregates, 0).kind == :exists ->
                  [aggregate] = aggregates

                  exists =
                    AshPostgres.Expr.dynamic_expr(
                      query,
                      %Ash.Query.Exists{path: aggregate.relationship_path, expr: true},
                      query.__ash_bindings__
                    )

                  {:cont, {:ok, query, [{aggregate.load, aggregate.name, exists} | dynamics]}}

                true ->
                  with {:ok, agg_root_query} <-
                         AshPostgres.Join.maybe_get_resource_query(
                           first_relationship.destination,
                           first_relationship,
                           query,
                           false,
                           [first_relationship.name],
                           nil,
                           nil,
                           true,
                           true
                         ),
                       agg_root_query <-
                         Map.update!(
                           agg_root_query,
                           :__ash_bindings__,
                           &Map.put(&1, :in_group?, true)
                         ),
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
                           Ash.Resource.Info.related(
                             first_relationship.destination,
                             relationship_path
                           ),
                           first_relationship
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
            end
          )

        case result do
          {:ok, query, dynamics} ->
            {:ok, add_aggregate_selects(query, dynamics, aggregate_name_mapping)}

          {:error, error} ->
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp use_aggregate_name(query, aggregate_name) do
    {%{
       query
       | __ash_bindings__: %{
           query.__ash_bindings__
           | current_aggregate_name:
               next_aggregate_name(query.__ash_bindings__.current_aggregate_name),
             aggregate_names:
               Map.put(
                 query.__ash_bindings__.aggregate_names,
                 aggregate_name,
                 query.__ash_bindings__.current_aggregate_name
               )
         }
     }, query.__ash_bindings__.current_aggregate_name}
  end

  defp resource_aggregates_to_aggregates(resource, aggregates) do
    aggregates
    |> Enum.reduce_while({:ok, []}, fn
      %Ash.Query.Aggregate{} = aggregate, {:ok, aggregates} ->
        {:cont, {:ok, [aggregate | aggregates]}}

      aggregate, {:ok, aggregates} ->
        related = Ash.Resource.Info.related(resource, aggregate.relationship_path)

        read_action =
          aggregate.read_action || Ash.Resource.Info.primary_action!(related, :read).name

        with %{valid?: true} = aggregate_query <- Ash.Query.for_read(related, read_action),
             %{valid?: true} = aggregate_query <-
               Ash.Query.build(aggregate_query, filter: aggregate.filter, sort: aggregate.sort) do
          Ash.Query.Aggregate.new(
            resource,
            aggregate.name,
            aggregate.kind,
            path: aggregate.relationship_path,
            query: aggregate_query,
            field: aggregate.field,
            default: aggregate.default,
            filterable?: aggregate.filterable?,
            type: aggregate.type,
            constraints: aggregate.constraints,
            implementation: aggregate.implementation,
            uniq?: aggregate.uniq?,
            read_action:
              aggregate.read_action ||
                Ash.Resource.Info.primary_action!(
                  Ash.Resource.Info.related(resource, aggregate.relationship_path),
                  :read
                ).name,
            authorize?: aggregate.authorize?
          )
        else
          %{valid?: false, errors: errors} ->
            {:error, errors}

          {:error, error} ->
            {:error, error}
        end
        |> case do
          {:ok, aggregate} ->
            {:cont, {:ok, [aggregate | aggregates]}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
    end)
  end

  defp add_first_join_aggregate(query, resource, aggregate, root_data) do
    {resource, path} =
      case root_data do
        {resource, path} ->
          {resource, path}

        _ ->
          {resource, []}
      end

    case AshPostgres.Join.join_all_relationships(
           query,
           nil,
           [],
           [
             {:left,
              AshPostgres.Join.relationship_path_to_relationships(
                resource,
                path ++ aggregate.relationship_path
              )}
           ],
           [],
           nil,
           false
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
         first_relationship,
         relationship_path,
         aggregates,
         is_single?,
         source_binding
       ) do
    Enum.reduce_while(aggregates, {:ok, agg_query}, fn aggregate, {:ok, agg_query} ->
      filter =
        if aggregate.query.filter do
          Ash.Filter.move_to_relationship_path(
            aggregate.query.filter,
            relationship_path
          )
          |> Map.put(:resource, first_relationship.destination)
        else
          aggregate.query.filter
        end

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
          if has_filter?(aggregate.query) && is_single? do
            {:cont,
             AshPostgres.DataLayer.filter(agg_query, filter, agg_query.__ash_bindings__.resource)}
          else
            {:cont, {:ok, agg_query}}
          end

        other ->
          {:halt, other}
      end
    end)
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
      from(row in subquery, distinct: true)

    new_subquery =
      if Map.get(first_relationship, :no_attributes?) do
        new_subquery
      else
        from(row in new_subquery,
          group_by: field(row, ^field),
          select_merge: map(row, ^[field])
        )
      end

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
        as: ^query.__ash_bindings__.current,
        on: true
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
        false,
        [join_relationship],
        nil,
        subquery.__ash_bindings__.current,
        true,
        true
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
        as: ^query.__ash_bindings__.current,
        on: true
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
      if Map.get(first_relationship, :no_attributes?) do
        subquery
      else
        from(row in subquery,
          group_by: field(row, ^field),
          select_merge: map(row, ^[field]),
          where:
            field(parent_as(^source_binding), ^first_relationship.source_attribute) ==
              field(as(^0), ^first_relationship.destination_attribute)
        )
      end

    subquery = AshPostgres.Join.set_join_prefix(subquery, query, first_relationship.destination)

    query =
      from(row in query,
        left_lateral_join: agg in subquery(subquery_if_distinct(subquery)),
        as: ^query.__ash_bindings__.current,
        on: true
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

  def next_aggregate_name(i) do
    @next_aggregate_names[i] ||
      raise Ash.Error.Framework.AssumptionFailed,
        message: """
        All 1000 static names for aggregates have been used in a single query.
        Congratulations, this means that you have gone so wildly beyond our imagination
        of how much can fit into a single quer. Please file an issue and we will raise the limit.
        """
  end

  defp subquery_if_distinct(%{distinct: nil} = query), do: query

  defp subquery_if_distinct(subquery) do
    from(row in subquery(subquery),
      select: row
    )
  end

  defp select_all_aggregates(
         aggregates,
         joined,
         relationship_path,
         _query,
         is_single?,
         resource,
         first_relationship
       ) do
    Enum.reduce(aggregates, joined, fn aggregate, joined ->
      add_subquery_aggregate_select(
        joined,
        relationship_path,
        aggregate,
        resource,
        is_single?,
        first_relationship
      )
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
        nil,
        false
      )
    end
  end

  defp can_group?(_, %{kind: :exists}), do: false
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
      if array_type?(resource, aggregate) || optimizable_first_aggregate?(resource, aggregate) do
        false
      else
        true
      end
    else
      true
    end
  end

  @doc false
  def optimizable_first_aggregate?(resource, %{
        name: name,
        kind: :first,
        relationship_path: relationship_path
      }) do
    name in AshPostgres.DataLayer.Info.simple_join_first_aggregates(resource) ||
      single_path?(resource, relationship_path)
  end

  def optimizable_first_aggregate?(_, _), do: false

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

  defp add_aggregate_selects(query, dynamics, name_mapping) do
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
            {name_mapping[name] || name, dynamic}
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
        is_single?,
        first_relationship
      ) do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)

    ref = %Ash.Query.Ref{
      attribute: aggregate_field(aggregate, resource, relationship_path, query),
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

    has_sort? = has_sort?(aggregate.query)

    sorted =
      if has_sort? || first_relationship.sort not in [nil, []] do
        {sort, binding} =
          if has_sort? do
            {aggregate.query.sort, binding}
          else
            {List.wrap(first_relationship.sort), 0}
          end

        {:ok, sort_expr, query} =
          AshPostgres.Sort.sort(
            query,
            sort,
            Ash.Resource.Info.related(
              query.__ash_bindings__.resource,
              relationship_path
            ),
            relationship_path,
            binding,
            :return
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
        is_single?,
        first_relationship
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
      attribute: aggregate_field(aggregate, resource, relationship_path, query),
      relationship_path: relationship_path,
      resource: query.__ash_bindings__.resource
    }

    field = AshPostgres.Expr.dynamic_expr(query, ref, query.__ash_bindings__, false)

    has_sort? = has_sort?(aggregate.query)

    sorted =
      if has_sort? || first_relationship.sort not in [nil, []] do
        {sort, binding} =
          if has_sort? do
            {aggregate.query.sort, binding}
          else
            {List.wrap(first_relationship.sort), 0}
          end

        {:ok, sort_expr, query} =
          AshPostgres.Sort.sort(
            query,
            sort,
            Ash.Resource.Info.related(
              query.__ash_bindings__.resource,
              relationship_path
            ),
            relationship_path,
            binding,
            :return
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
        Ecto.Query.dynamic(type(^with_default, ^type))
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
        is_single?,
        _first_relationship
      )
      when kind in [:count, :sum, :avg, :max, :min, :custom] do
    query = AshPostgres.DataLayer.default_bindings(query, aggregate.resource)

    ref = %Ash.Query.Ref{
      attribute: aggregate_field(aggregate, resource, relationship_path, query),
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
            Ecto.Query.dynamic([row], count(^field))
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

  defp single_path?(_, []), do: true

  defp single_path?(resource, [relationship | rest]) do
    relationship = Ash.Resource.Info.relationship(resource, relationship)
    relationship.type == :belongs_to && single_path?(relationship.destination, rest)
  end

  defp aggregate_field(aggregate, resource, _relationship_path, query) do
    case Ash.Resource.Info.field(
           resource,
           aggregate.field || List.first(Ash.Resource.Info.primary_key(resource))
         ) do
      %Ash.Resource.Calculation{calculation: {module, opts}} = calculation ->
        calc_type =
          AshPostgres.Types.parameterized_type(
            calculation.type,
            Map.get(calculation, :constraints, [])
          )

        AshPostgres.Expr.validate_type!(query, calc_type, "#{inspect(calculation.name)}")

        {:ok, query_calc} =
          Ash.Query.Calculation.new(
            calculation.name,
            module,
            opts,
            calculation.type,
            Map.get(aggregate, :context, %{})
          )

        query_calc

      other ->
        other
    end
  end
end
