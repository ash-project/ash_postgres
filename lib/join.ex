defmodule AshPostgres.Join do
  @moduledoc false
  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Ash.Query.{BooleanExpression, Not, Ref}

  @known_inner_join_operators [
                                Eq,
                                GreaterThan,
                                GreaterThanOrEqual,
                                In,
                                LessThanOrEqual,
                                LessThan,
                                NotEq
                              ]
                              |> Enum.map(&Module.concat(Ash.Query.Operator, &1))

  @known_inner_join_functions [
                                Ago,
                                Contains
                              ]
                              |> Enum.map(&Module.concat(Ash.Query.Function, &1))

  @known_inner_join_predicates @known_inner_join_functions ++ @known_inner_join_operators

  def join_all_relationships(
        query,
        filter,
        opts \\ [],
        relationship_paths \\ nil,
        path \\ [],
        source \\ nil,
        sort? \\ true
      )

  # simple optimization for common cases
  def join_all_relationships(query, filter, _opts, relationship_paths, _path, _source, _sort?)
      when is_nil(relationship_paths) and filter in [nil, true, false] do
    {:ok, query}
  end

  def join_all_relationships(
        query,
        filter,
        opts,
        relationship_paths,
        path,
        source,
        sort?
      ) do
    relationship_paths =
      cond do
        relationship_paths ->
          relationship_paths

        opts[:no_this?] ->
          filter
          |> Ash.Filter.map(fn
            %Ash.Query.Parent{} ->
              nil

            other ->
              other
          end)
          |> Ash.Filter.relationship_paths()
          |> to_joins(filter, query.__ash_bindings__.resource)

        true ->
          filter
          |> Ash.Filter.relationship_paths()
          |> to_joins(filter, query.__ash_bindings__.resource)
      end

    Enum.reduce_while(relationship_paths, {:ok, query}, fn
      {_join_type, []}, {:ok, query} ->
        {:cont, {:ok, query}}

      {join_type, [relationship | rest_rels]}, {:ok, query} ->
        source = source || relationship.source

        current_path = path ++ [relationship]

        current_join_type = join_type

        look_for_join_types =
          case join_type do
            :left ->
              [:left, :inner]

            :inner ->
              [:left, :inner]

            other ->
              [other]
          end

        case get_binding(source, Enum.map(current_path, & &1.name), query, look_for_join_types) do
          binding when is_integer(binding) ->
            case join_all_relationships(
                   query,
                   filter,
                   opts,
                   [{join_type, rest_rels}],
                   current_path,
                   source
                 ) do
              {:ok, query} ->
                {:cont, {:ok, query}}

              {:error, error} ->
                {:halt, {:error, error}}
            end

          nil ->
            case join_relationship(
                   query,
                   relationship,
                   Enum.map(path, & &1.name),
                   current_join_type,
                   source,
                   filter,
                   sort?
                 ) do
              {:ok, joined_query} ->
                joined_query_with_distinct = add_distinct(relationship, join_type, joined_query)

                case join_all_relationships(
                       joined_query_with_distinct,
                       filter,
                       opts,
                       [{join_type, rest_rels}],
                       current_path,
                       source
                     ) do
                  {:ok, query} ->
                    {:cont, {:ok, query}}

                  {:error, error} ->
                    {:halt, {:error, error}}
                end

              {:error, error} ->
                {:halt, {:error, error}}
            end
        end
    end)
  end

  defp to_joins(paths, filter, resource) do
    paths
    |> Enum.reject(&(&1 == []))
    |> Enum.map(fn path ->
      if can_inner_join?(path, filter) do
        {:inner,
         AshPostgres.Join.relationship_path_to_relationships(
           resource,
           path
         )}
      else
        {:left,
         AshPostgres.Join.relationship_path_to_relationships(
           resource,
           path
         )}
      end
    end)
  end

  # defp expand_join_paths(joins) do
  #   Enum.flat_map(joins, fn {type, path} ->
  #     path
  #     |> sub_paths()
  #     |> Enum.map(&add_relationship_filter_paths/1)
  #   end)
  # end

  # defp add_relationship_filter_paths(path) do
  #   last = List.last(path)
  #   prefix = :lists.droplast(path)

  # end

  # defp sub_paths(path) do
  #   Enum.map(1..Enum.count(path), fn i ->
  #     Enum.take(path, i)
  #   end)
  # end

  def relationship_path_to_relationships(resource, path, acc \\ [])
  def relationship_path_to_relationships(_resource, [], acc), do: Enum.reverse(acc)

  def relationship_path_to_relationships(resource, [relationship | rest], acc) do
    relationship = Ash.Resource.Info.relationship(resource, relationship)

    relationship_path_to_relationships(relationship.destination, rest, [relationship | acc])
  end

  def maybe_get_resource_query(
        resource,
        relationship,
        root_query,
        sort?,
        path \\ [],
        bindings \\ nil,
        start_binding \\ nil,
        is_subquery? \\ true,
        join_relationships? \\ false
      ) do
    resource
    |> Ash.Query.new(nil, base_filter?: false)
    |> Ash.Query.set_context(%{data_layer: %{start_bindings_at: start_binding}})
    |> Ash.Query.set_context((bindings || root_query.__ash_bindings__).context)
    |> Ash.Query.set_context(relationship.context)
    |> case do
      %{valid?: true} = query ->
        ash_query = query

        initial_query =
          %{
            AshPostgres.DataLayer.resource_to_query(resource, nil)
            | prefix: Map.get(root_query, :prefix)
          }

        initial_query = do_relationship_sort(initial_query, relationship, sort?)

        case Ash.Query.data_layer_query(query,
               initial_query: initial_query
             ) do
          {:ok, query} ->
            query =
              if join_relationships? do
                {:ok, related_filter} =
                  Ash.Filter.hydrate_refs(
                    relationship.filter,
                    %{
                      resource: relationship.destination,
                      public?: false
                    }
                  )

                {:ok, query} =
                  AshPostgres.Join.join_all_relationships(query, related_filter)

                query
              else
                query
              end

            query =
              query
              |> do_base_filter(
                root_query,
                ash_query,
                resource,
                path,
                bindings
              )
              |> do_relationship_filter(
                relationship,
                root_query,
                ash_query,
                resource,
                path,
                bindings,
                is_subquery?
              )

            {:ok, query}

          {:error, error} ->
            {:error, error}
        end

      query ->
        {:error, query}
    end
  end

  defp do_relationship_sort(
         query,
         %{destination: destination, sort: sort, from_many?: true},
         true
       )
       when sort not in [nil, []] do
    query =
      if query.aliases[0] do
        query
      else
        from(row in query, as: ^0)
      end

    query = AshPostgres.DataLayer.default_bindings(query, destination)

    {:ok, order_by, query} =
      AshPostgres.Sort.sort(query, sort, query.__ash_bindings__.resource, [], 0, :return)

    from(row in subquery(Ecto.Query.order_by(query, ^order_by)), [])
    |> AshPostgres.DataLayer.default_bindings(destination)
    |> Map.update!(:__ash_bindings__, &Map.put(&1, :current, query.__ash_bindings__.current))
  end

  defp do_relationship_sort(query, _, _), do: query

  defp do_relationship_filter(query, %{filter: nil}, _, _, _, _, _, _), do: query

  defp do_relationship_filter(
         query,
         relationship,
         root_query,
         ash_query,
         resource,
         path,
         bindings,
         is_subquery?
       ) do
    filter =
      resource
      |> Ash.Filter.parse!(
        relationship.filter,
        ash_query.aggregates,
        ash_query.calculations,
        Map.update(
          ash_query.context,
          :parent_stack,
          [relationship.source],
          &[&1 | relationship.source]
        )
      )

    base_bindings = bindings || query.__ash_bindings__

    parent_binding =
      case :lists.droplast(path) do
        [] ->
          base_bindings.bindings
          |> Enum.find_value(fn {key, %{type: type}} ->
            if type == :root do
              key
            end
          end)

        path ->
          get_binding(
            root_query.__ash_bindings__.resource,
            path,
            %{query | __ash_bindings__: base_bindings},
            [
              :inner,
              :left
            ]
          )
      end

    parent_bindings = %{
      base_bindings
      | resource: relationship.source,
        calculations: %{},
        parent_resources: [],
        aggregate_defs: %{},
        context: relationship.context,
        current: parent_binding + 1
    }

    parent_bindings =
      if bindings do
        Map.put(parent_bindings, :parent_is_parent_as?, !is_subquery?)
      else
        parent_bindings
        |> Map.update!(:bindings, &Map.take(&1, [parent_binding]))
      end

    has_bindings? = not is_nil(bindings)

    bindings =
      base_bindings
      |> Map.put(:parent_bindings, parent_bindings)
      |> Map.put(:parent_resources, [
        relationship.source | parent_bindings[:parent_resources] || []
      ])

    dynamic =
      if has_bindings? do
        filter =
          if is_subquery? do
            Ash.Filter.move_to_relationship_path(filter, path)
          else
            filter
          end

        AshPostgres.Expr.dynamic_expr(root_query, filter, bindings, true)
      else
        AshPostgres.Expr.dynamic_expr(query, filter, bindings, true)
      end

    from(row in query, where: ^dynamic)
  end

  defp do_base_filter(query, root_query, ash_query, resource, path, bindings) do
    case Ash.Resource.Info.base_filter(resource) do
      nil ->
        query

      filter ->
        filter =
          resource
          |> Ash.Filter.parse!(
            filter,
            ash_query.aggregates,
            ash_query.calculations,
            ash_query.context
          )

        dynamic =
          if bindings do
            filter = Ash.Filter.move_to_relationship_path(filter, path)

            AshPostgres.Expr.dynamic_expr(root_query, filter, bindings, true)
          else
            AshPostgres.Expr.dynamic_expr(query, filter, query.__ash_bindings__, true)
          end

        from(row in query, where: ^dynamic)
    end
  end

  def set_join_prefix(join_query, query, resource) do
    if Ash.Resource.Info.multitenancy_strategy(resource) == :context do
      %{
        join_query
        | prefix: query.prefix || AshPostgres.DataLayer.Info.schema(resource) || "public"
      }
    else
      %{
        join_query
        | prefix:
            AshPostgres.DataLayer.Info.schema(resource) ||
              AshPostgres.DataLayer.Info.repo(resource, :mutate).config()[:default_prefix] ||
              "public"
      }
    end
  end

  defp can_inner_join?(path, expr, seen_an_or? \\ false)

  defp can_inner_join?(path, %{expression: expr}, seen_an_or?),
    do: can_inner_join?(path, expr, seen_an_or?)

  defp can_inner_join?(_path, expr, _seen_an_or?) when expr in [nil, true, false], do: true

  defp can_inner_join?(path, %BooleanExpression{op: :and, left: left, right: right}, seen_an_or?) do
    can_inner_join?(path, left, seen_an_or?) || can_inner_join?(path, right, seen_an_or?)
  end

  defp can_inner_join?(path, %BooleanExpression{op: :or, left: left, right: right}, _) do
    can_inner_join?(path, left, true) && can_inner_join?(path, right, true)
  end

  defp can_inner_join?(
         _,
         %Not{},
         _
       ) do
    false
  end

  defp can_inner_join?(
         search_path,
         %struct{__operator__?: true, left: %Ref{relationship_path: relationship_path}},
         seen_an_or?
       )
       when search_path == relationship_path and struct in @known_inner_join_predicates do
    not seen_an_or?
  end

  defp can_inner_join?(
         search_path,
         %struct{__operator__?: true, right: %Ref{relationship_path: relationship_path}},
         seen_an_or?
       )
       when search_path == relationship_path and struct in @known_inner_join_predicates do
    not seen_an_or?
  end

  defp can_inner_join?(
         search_path,
         %struct{__function__?: true, arguments: arguments},
         seen_an_or?
       )
       when struct in @known_inner_join_predicates do
    if Enum.any?(arguments, &match?(%Ref{relationship_path: ^search_path}, &1)) do
      not seen_an_or?
    else
      true
    end
  end

  defp can_inner_join?(_, _, _), do: false

  @doc false
  def get_binding(resource, candidate_path, %{__ash_bindings__: _} = query, types) do
    types = List.wrap(types)

    Enum.find_value(query.__ash_bindings__.bindings, fn
      {binding, %{path: path, source: source, type: type}} ->
        if type in types &&
             Ash.SatSolver.synonymous_relationship_paths?(resource, path, candidate_path, source) do
          binding
        end

      _ ->
        nil
    end)
  end

  def get_binding(_, _, _, _), do: nil

  defp add_distinct(relationship, _join_type, joined_query) do
    if !joined_query.__ash_bindings__.in_group? &&
         (relationship.cardinality == :many || Map.get(relationship, :from_many?)) &&
         !joined_query.distinct do
      from(row in joined_query,
        distinct: ^Ash.Resource.Info.primary_key(joined_query.__ash_bindings__.resource)
      )
    else
      joined_query
    end
  end

  defp join_relationship(
         query,
         relationship,
         path,
         join_type,
         source,
         filter,
         sort?
       ) do
    case Map.get(query.__ash_bindings__.bindings, path) do
      %{type: existing_join_type} when join_type != existing_join_type ->
        raise "unreachable?"

      nil ->
        do_join_relationship(
          query,
          relationship,
          path,
          join_type,
          source,
          filter,
          sort?
        )

      _ ->
        {:ok, query}
    end
  end

  defp do_join_relationship(
         query,
         %{manual: {module, opts}} = relationship,
         path,
         kind,
         source,
         filter,
         sort?
       ) do
    full_path = path ++ [relationship.name]
    initial_ash_bindings = query.__ash_bindings__

    binding_data = %{type: kind, path: full_path, source: source}

    query = AshPostgres.DataLayer.add_binding(query, binding_data)

    used_calculations =
      Ash.Filter.used_calculations(
        filter,
        relationship.destination,
        full_path
      )

    used_aggregates =
      filter
      |> AshPostgres.Aggregate.used_aggregates(
        relationship.destination,
        used_calculations,
        full_path
      )
      |> Enum.map(fn aggregate ->
        %{aggregate | load: aggregate.name}
      end)

    use_root_query_bindings? = Enum.empty?(used_aggregates)

    root_bindings =
      if use_root_query_bindings? do
        query.__ash_bindings__
      end

    case maybe_get_resource_query(
           relationship.destination,
           relationship,
           query,
           sort?,
           full_path,
           root_bindings
         ) do
      {:error, error} ->
        {:error, error}

      {:ok, relationship_destination} ->
        relationship_destination =
          relationship_destination
          |> Ecto.Queryable.to_query()
          |> set_join_prefix(query, relationship.destination)

        binding_kinds =
          case kind do
            :left ->
              [:left, :inner]

            :inner ->
              [:left, :inner]

            other ->
              [other]
          end

        current_binding =
          Enum.find_value(initial_ash_bindings.bindings, 0, fn {binding, data} ->
            if data.type in binding_kinds && data.path == path do
              binding
            end
          end)

        needs_subquery? =
          used_aggregates != [] || Map.get(relationship, :from_many?)

        relationship_destination =
          if needs_subquery? do
            subquery(relationship_destination)
          else
            relationship_destination
          end

        case module.ash_postgres_join(
               query,
               opts,
               current_binding,
               initial_ash_bindings.current,
               kind,
               relationship_destination
             ) do
          {:ok, query} ->
            AshPostgres.Aggregate.add_aggregates(
              query,
              used_aggregates,
              relationship.destination,
              false,
              initial_ash_bindings.current,
              {query.__ash_bindings__.resource, full_path}
            )
        end
    end
  rescue
    e in UndefinedFunctionError ->
      if e.function == :ash_postgres_join do
        reraise """
                Cannot join to a manual relationship #{inspect(module)} that does not implement the `AshPostgres.ManualRelationship` behaviour.
                """,
                __STACKTRACE__
      else
        reraise e, __STACKTRACE__
      end
  end

  defp do_join_relationship(
         query,
         %{type: :many_to_many} = relationship,
         path,
         kind,
         source,
         filter,
         sort?
       ) do
    join_relationship =
      Ash.Resource.Info.relationship(relationship.source, relationship.join_relationship)

    join_path = path ++ [join_relationship.name]

    full_path = path ++ [relationship.name]

    initial_ash_bindings = query.__ash_bindings__

    binding_data = %{type: kind, path: full_path, source: source}

    query =
      query
      |> AshPostgres.DataLayer.add_binding(%{
        path: join_path,
        type: :left,
        source: source
      })
      |> AshPostgres.DataLayer.add_binding(binding_data)

    {:ok, related_filter} =
      Ash.Filter.hydrate_refs(
        relationship.filter,
        %{
          resource: relationship.destination,
          aggregates: %{},
          calculations: %{},
          public?: false
        }
      )

    related_filter =
      Ash.Filter.move_to_relationship_path(related_filter, full_path)

    {:ok, query} = join_all_relationships(query, related_filter)

    used_calculations =
      Ash.Filter.used_calculations(
        filter,
        relationship.destination,
        full_path
      )

    used_aggregates =
      filter
      |> AshPostgres.Aggregate.used_aggregates(
        relationship.destination,
        used_calculations,
        full_path
      )
      |> Enum.map(fn aggregate ->
        %{aggregate | load: aggregate.name}
      end)

    use_root_query_bindings? = Enum.empty?(used_aggregates)

    root_bindings =
      if use_root_query_bindings? do
        query.__ash_bindings__
      end

    with {:ok, relationship_through} <-
           maybe_get_resource_query(
             relationship.through,
             join_relationship,
             query,
             false,
             join_path,
             root_bindings
           ),
         {:ok, relationship_destination} <-
           maybe_get_resource_query(
             relationship.destination,
             relationship,
             query,
             sort?,
             path,
             root_bindings
           ) do
      relationship_through =
        relationship_through
        |> Ecto.Queryable.to_query()
        |> set_join_prefix(query, relationship.through)

      relationship_destination =
        relationship_destination
        |> Ecto.Queryable.to_query()
        |> set_join_prefix(query, relationship.destination)

      binding_kinds =
        case kind do
          :left ->
            [:left, :inner]

          :inner ->
            [:left, :inner]

          other ->
            [other]
        end

      current_binding =
        Enum.find_value(initial_ash_bindings.bindings, 0, fn {binding, data} ->
          if data.type in binding_kinds && data.path == path do
            binding
          end
        end)

      needs_subquery? =
        used_aggregates != [] || Map.get(relationship, :from_many?)

      relationship_destination =
        if needs_subquery? do
          subquery(relationship_destination)
        else
          relationship_destination
        end

      query =
        case kind do
          :inner ->
            from([{row, current_binding}] in query,
              join: through in ^relationship_through,
              as: ^initial_ash_bindings.current,
              on:
                field(row, ^relationship.source_attribute) ==
                  field(through, ^relationship.source_attribute_on_join_resource),
              join: destination in ^relationship_destination,
              as: ^(initial_ash_bindings.current + 1),
              on:
                field(destination, ^relationship.destination_attribute) ==
                  field(through, ^relationship.destination_attribute_on_join_resource)
            )

          _ ->
            from([{row, current_binding}] in query,
              left_join: through in ^relationship_through,
              as: ^initial_ash_bindings.current,
              on:
                field(row, ^relationship.source_attribute) ==
                  field(through, ^relationship.source_attribute_on_join_resource),
              left_join: destination in ^relationship_destination,
              as: ^(initial_ash_bindings.current + 1),
              on:
                field(destination, ^relationship.destination_attribute) ==
                  field(through, ^relationship.destination_attribute_on_join_resource)
            )
        end

      AshPostgres.Aggregate.add_aggregates(
        query,
        used_aggregates,
        relationship.destination,
        false,
        initial_ash_bindings.current,
        {query.__ash_bindings__.resource, full_path}
      )
    end
  end

  defp do_join_relationship(
         query,
         relationship,
         path,
         kind,
         source,
         filter,
         sort?
       ) do
    full_path = path ++ [relationship.name]
    initial_ash_bindings = query.__ash_bindings__

    binding_data = %{type: kind, path: full_path, source: source}

    query = AshPostgres.DataLayer.add_binding(query, binding_data)

    {:ok, related_filter} =
      Ash.Filter.hydrate_refs(
        relationship.filter,
        %{
          resource: relationship.destination,
          public?: false
        }
      )

    related_filter =
      Ash.Filter.move_to_relationship_path(related_filter, full_path)

    {:ok, query} = join_all_relationships(query, related_filter)

    used_calculations =
      Ash.Filter.used_calculations(
        filter,
        relationship.destination,
        full_path
      )

    used_aggregates =
      filter
      |> AshPostgres.Aggregate.used_aggregates(
        relationship.destination,
        used_calculations,
        full_path
      )
      |> Enum.map(fn aggregate ->
        %{aggregate | load: aggregate.name}
      end)

    use_root_query_bindings? = Enum.empty?(used_aggregates)

    root_bindings =
      if use_root_query_bindings? do
        query.__ash_bindings__
      end

    case maybe_get_resource_query(
           relationship.destination,
           relationship,
           query,
           sort?,
           full_path,
           root_bindings
         ) do
      {:error, error} ->
        {:error, error}

      {:ok, relationship_destination} ->
        relationship_destination =
          relationship_destination
          |> Ecto.Queryable.to_query()
          |> set_join_prefix(query, relationship.destination)

        needs_subquery? = Map.get(relationship, :from_many?)

        relationship_destination =
          if needs_subquery? do
            subquery(relationship_destination)
          else
            relationship_destination
          end

        binding_kinds =
          case kind do
            :left ->
              [:left, :inner]

            :inner ->
              [:left, :inner]

            other ->
              [other]
          end

        current_binding =
          Enum.find_value(initial_ash_bindings.bindings, 0, fn {binding, data} ->
            if data.type in binding_kinds && data.path == path do
              binding
            end
          end)

        relationship_destination =
          used_aggregates
          |> Enum.reject(fn aggregate ->
            AshPostgres.Aggregate.optimizable_first_aggregate?(
              relationship.destination,
              aggregate
            )
          end)
          |> case do
            [] ->
              relationship_destination

            _ ->
              subquery(relationship_destination)
          end

        query =
          case {kind, Map.get(relationship, :no_attributes?)} do
            {:inner, true} ->
              from([{row, current_binding}] in query,
                join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
              )

            {_, true} ->
              from([{row, current_binding}] in query,
                left_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
              )

            {:inner, _} ->
              from([{row, current_binding}] in query,
                join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on:
                  field(row, ^relationship.source_attribute) ==
                    field(
                      destination,
                      ^relationship.destination_attribute
                    )
              )

            _ ->
              from([{row, current_binding}] in query,
                left_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on:
                  field(row, ^relationship.source_attribute) ==
                    field(
                      destination,
                      ^relationship.destination_attribute
                    )
              )
          end

        AshPostgres.Aggregate.add_aggregates(
          query,
          used_aggregates,
          relationship.destination,
          false,
          initial_ash_bindings.current,
          {query.__ash_bindings__.resource, full_path}
        )
    end
  end
end
