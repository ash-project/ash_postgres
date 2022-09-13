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
        relationship_paths \\ nil,
        path \\ [],
        source \\ nil
      ) do
    relationship_paths =
      relationship_paths ||
        filter
        |> Ash.Filter.relationship_paths()
        |> Enum.map(fn path ->
          if can_inner_join?(path, filter) do
            {:inner, AshPostgres.Join.relationship_path_to_relationships(filter.resource, path)}
          else
            {:left, AshPostgres.Join.relationship_path_to_relationships(filter.resource, path)}
          end
        end)

    Enum.reduce_while(relationship_paths, {:ok, query}, fn
      {_join_type, []}, {:ok, query} ->
        {:cont, {:ok, query}}

      {join_type, [relationship | rest_rels]}, {:ok, query} ->
        source = source || relationship.source

        current_path = path ++ [relationship]

        current_join_type =
          case join_type do
            {:aggregate, _name, _agg} when rest_rels != [] ->
              :left

            other ->
              other
          end

        if has_binding?(source, Enum.reverse(current_path), query, current_join_type) do
          {:cont, {:ok, query}}
        else
          case join_relationship(
                 query,
                 relationship,
                 Enum.map(path, & &1.name),
                 current_join_type,
                 source,
                 filter
               ) do
            {:ok, joined_query} ->
              joined_query_with_distinct = add_distinct(relationship, join_type, joined_query)

              case join_all_relationships(
                     joined_query_with_distinct,
                     filter,
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
        path \\ [],
        use_root_query_bindings? \\ false
      ) do
    resource
    |> Ash.Query.new(nil, base_filter?: false)
    |> Ash.Query.set_context(root_query.__ash_bindings__.context)
    |> Ash.Query.set_context(relationship.context)
    |> case do
      %{valid?: true} = query ->
        ash_query = query

        initial_query = %{
          AshPostgres.DataLayer.resource_to_query(resource, nil)
          | prefix: Map.get(root_query, :prefix)
        }

        case Ash.Query.data_layer_query(query,
               initial_query: initial_query
             ) do
          {:ok, query} ->
            query =
              query
              |> do_base_filter(
                root_query,
                ash_query,
                resource,
                path,
                use_root_query_bindings?
              )
              |> do_relationship_filter(
                relationship.filter,
                root_query,
                ash_query,
                resource,
                path
              )

            {:ok, query}

          {:error, error} ->
            {:error, error}
        end

      query ->
        {:error, query}
    end
  end

  defp do_relationship_filter(query, nil, _, _, _, _), do: query

  defp do_relationship_filter(
         query,
         relationship_filter,
         root_query,
         ash_query,
         resource,
         path
       ) do
    filter =
      resource
      |> Ash.Filter.parse!(
        relationship_filter,
        ash_query.aggregates,
        ash_query.calculations,
        ash_query.context
      )

    dynamic =
      AshPostgres.Expr.dynamic_expr(
        root_query,
        Ash.Filter.move_to_relationship_path(filter, path),
        root_query.__ash_bindings__,
        true
      )

    {:ok, query} = join_all_relationships(query, filter)
    from(row in query, where: ^dynamic)
  end

  defp do_base_filter(query, root_query, ash_query, resource, path, use_root_query_bindings?) do
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
          if use_root_query_bindings? do
            filter = Ash.Filter.move_to_relationship_path(filter, path)

            AshPostgres.Expr.dynamic_expr(root_query, filter, root_query.__ash_bindings__, true)
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
              AshPostgres.DataLayer.Info.repo(resource).config()[:default_prefix] ||
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

  defp has_binding?(resource, path, query, {:aggregate, _, _}),
    do: has_binding?(resource, path, query, :aggregate)

  defp has_binding?(resource, candidate_path, %{__ash_bindings__: _} = query, type) do
    Enum.any?(query.__ash_bindings__.bindings, fn
      {_, %{path: path, source: source, type: ^type}} ->
        Ash.SatSolver.synonymous_relationship_paths?(resource, path, candidate_path, source)

      _ ->
        false
    end)
  end

  defp has_binding?(_, _, _, _), do: false

  defp add_distinct(relationship, join_type, joined_query) do
    if relationship.cardinality == :many and join_type == :left && !joined_query.distinct do
      if joined_query.group_bys && joined_query.group_bys != [] do
        joined_query
      else
        from(row in joined_query,
          distinct: ^Ash.Resource.Info.primary_key(relationship.destination)
        )
      end
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
         filter
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
          filter
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
         filter
       ) do
    full_path = path ++ [relationship.name]
    initial_ash_bindings = query.__ash_bindings__

    binding_data =
      case kind do
        {:aggregate, name, _agg} ->
          %{type: :aggregate, name: name, path: full_path, source: source}

        _ ->
          %{type: kind, path: full_path, source: source}
      end

    query = AshPostgres.DataLayer.add_binding(query, binding_data)

    used_calculations =
      Ash.Filter.used_calculations(
        filter,
        relationship.destination,
        full_path
      )

    used_aggregates =
      filter
      |> AshPostgres.Aggregate.used_aggregates(relationship, used_calculations, full_path)
      |> Enum.map(fn aggregate ->
        %{aggregate | load: aggregate.name}
      end)

    use_root_query_bindings? = Enum.empty?(used_aggregates)

    case maybe_get_resource_query(
           relationship.destination,
           relationship,
           query,
           full_path,
           use_root_query_bindings?
         ) do
      {:error, error} ->
        {:error, error}

      {:ok, relationship_destination} ->
        relationship_destination =
          relationship_destination
          |> Ecto.Queryable.to_query()
          |> set_join_prefix(query, relationship.destination)

        binding_kind =
          case kind do
            {:aggregate, _, _} ->
              :left

            other ->
              other
          end

        current_binding =
          Enum.find_value(initial_ash_bindings.bindings, 0, fn {binding, data} ->
            if data.type == binding_kind && data.path == path do
              binding
            end
          end)

        relationship_destination
        |> AshPostgres.Aggregate.add_aggregates(used_aggregates, relationship.destination)
        |> case do
          {:ok, relationship_destination} ->
            relationship_destination =
              case used_aggregates do
                [] ->
                  relationship_destination

                _ ->
                  subquery(relationship_destination)
              end

            case kind do
              {:aggregate, _, subquery} ->
                case AshPostgres.Aggregate.agg_subquery_for_lateral_join(
                       current_binding,
                       query,
                       subquery,
                       relationship
                     ) do
                  {:ok, subquery} ->
                    {:ok,
                     from([{row, current_binding}] in query,
                       left_lateral_join: destination in ^subquery,
                       as: ^initial_ash_bindings.current
                     )}

                  other ->
                    other
                end

              kind ->
                module.ash_postgres_join(
                  query,
                  opts,
                  current_binding,
                  initial_ash_bindings.current,
                  kind,
                  relationship_destination
                )
            end

          {:error, error} ->
            {:error, error}
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
         filter
       ) do
    join_relationship =
      Ash.Resource.Info.relationship(relationship.source, relationship.join_relationship)

    join_path =
      Enum.reverse([
        String.to_existing_atom(to_string(relationship.name) <> "_join_assoc") | path
      ])

    full_path = path ++ [relationship.name]

    initial_ash_bindings = query.__ash_bindings__

    binding_data =
      case kind do
        {:aggregate, name, _agg} ->
          %{type: :aggregate, name: name, path: full_path, source: source}

        _ ->
          %{type: kind, path: full_path, source: source}
      end

    additional_binding? =
      case kind do
        {:aggregate, _, _subquery} ->
          false

        _ ->
          true
      end

    query =
      case kind do
        {:aggregate, _, _subquery} ->
          additional_bindings =
            if additional_binding? do
              1
            else
              0
            end

          query
          |> AshPostgres.DataLayer.add_binding(binding_data, additional_bindings)

        _ ->
          query
          |> AshPostgres.DataLayer.add_binding(%{
            path: join_path,
            type: :left,
            source: source
          })
          |> AshPostgres.DataLayer.add_binding(binding_data)
      end

    used_calculations =
      Ash.Filter.used_calculations(
        filter,
        relationship.destination,
        full_path
      )

    used_aggregates =
      filter
      |> AshPostgres.Aggregate.used_aggregates(relationship, used_calculations, full_path)
      |> Enum.map(fn aggregate ->
        %{aggregate | load: aggregate.name}
      end)

    use_root_query_bindings? = Enum.empty?(used_aggregates)

    with {:ok, relationship_through} <-
           maybe_get_resource_query(
             relationship.through,
             join_relationship,
             query,
             join_path,
             use_root_query_bindings?
           ),
         {:ok, relationship_destination} <-
           maybe_get_resource_query(
             relationship.destination,
             relationship,
             query,
             path,
             use_root_query_bindings?
           ) do
      relationship_through =
        relationship_through
        |> Ecto.Queryable.to_query()
        |> set_join_prefix(query, relationship.through)

      relationship_destination =
        relationship_destination
        |> Ecto.Queryable.to_query()
        |> set_join_prefix(query, relationship.destination)

      binding_kind =
        case kind do
          {:aggregate, _, _} ->
            :left

          other ->
            other
        end

      current_binding =
        Enum.find_value(initial_ash_bindings.bindings, 0, fn {binding, data} ->
          if data.type == binding_kind && data.path == path do
            binding
          end
        end)

      relationship_destination
      |> AshPostgres.Aggregate.add_aggregates(used_aggregates, relationship.destination)
      |> case do
        {:ok, relationship_destination} ->
          relationship_destination =
            case used_aggregates do
              [] ->
                relationship_destination

              _ ->
                subquery(relationship_destination)
            end

          case kind do
            {:aggregate, _, subquery} ->
              case AshPostgres.Aggregate.agg_subquery_for_lateral_join(
                     current_binding,
                     query,
                     subquery,
                     relationship
                   ) do
                {:ok, subquery} ->
                  {:ok,
                   from([{row, current_binding}] in query,
                     left_lateral_join: through in ^subquery,
                     as: ^initial_ash_bindings.current
                   )}

                other ->
                  other
              end

            :inner ->
              {:ok,
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
               )}

            _ ->
              {:ok,
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
               )}
          end

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp do_join_relationship(
         query,
         relationship,
         path,
         kind,
         source,
         filter
       ) do
    full_path = path ++ [relationship.name]
    initial_ash_bindings = query.__ash_bindings__

    binding_data =
      case kind do
        {:aggregate, name, _agg} ->
          %{type: :aggregate, name: name, path: full_path, source: source}

        _ ->
          %{type: kind, path: full_path, source: source}
      end

    query = AshPostgres.DataLayer.add_binding(query, binding_data)

    used_calculations =
      Ash.Filter.used_calculations(
        filter,
        relationship.destination,
        full_path
      )

    used_aggregates =
      filter
      |> AshPostgres.Aggregate.used_aggregates(relationship, used_calculations, full_path)
      |> Enum.map(fn aggregate ->
        %{aggregate | load: aggregate.name}
      end)

    use_root_query_bindings? = Enum.empty?(used_aggregates)

    case maybe_get_resource_query(
           relationship.destination,
           relationship,
           query,
           full_path,
           use_root_query_bindings?
         ) do
      {:error, error} ->
        {:error, error}

      {:ok, relationship_destination} ->
        relationship_destination =
          relationship_destination
          |> Ecto.Queryable.to_query()
          |> set_join_prefix(query, relationship.destination)

        binding_kind =
          case kind do
            {:aggregate, _, _} ->
              :left

            other ->
              other
          end

        current_binding =
          Enum.find_value(initial_ash_bindings.bindings, 0, fn {binding, data} ->
            if data.type == binding_kind && data.path == path do
              binding
            end
          end)

        relationship_destination
        |> AshPostgres.Aggregate.add_aggregates(used_aggregates, relationship.destination)
        |> case do
          {:ok, relationship_destination} ->
            relationship_destination =
              case used_aggregates do
                [] ->
                  relationship_destination

                _ ->
                  subquery(relationship_destination)
              end

            case {kind, Map.get(relationship, :no_attributes?)} do
              {{:aggregate, _, subquery}, _} ->
                case AshPostgres.Aggregate.agg_subquery_for_lateral_join(
                       current_binding,
                       query,
                       subquery,
                       relationship
                     ) do
                  {:ok, subquery} ->
                    {:ok,
                     from([{row, current_binding}] in query,
                       left_lateral_join: destination in ^subquery,
                       as: ^initial_ash_bindings.current
                     )}

                  other ->
                    other
                end

              {_, true} ->
                from([{row, current_binding}] in query,
                  join: destination in ^relationship_destination,
                  as: ^initial_ash_bindings.current
                )

              {:inner, _} ->
                {:ok,
                 from([{row, current_binding}] in query,
                   join: destination in ^relationship_destination,
                   as: ^initial_ash_bindings.current,
                   on:
                     field(row, ^relationship.source_attribute) ==
                       field(destination, ^relationship.destination_attribute)
                 )}

              _ ->
                {:ok,
                 from([{row, current_binding}] in query,
                   left_join: destination in ^relationship_destination,
                   as: ^initial_ash_bindings.current,
                   on:
                     field(row, ^relationship.source_attribute) ==
                       field(destination, ^relationship.destination_attribute)
                 )}
            end

          {:error, error} ->
            {:error, error}
        end
    end
  end
end
