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

  def join_all_relationships(query, filter, relationship_paths \\ nil, path \\ [], source \\ nil) do
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

  def maybe_get_resource_query(resource, relationship, root_query) do
    resource
    |> Ash.Query.new()
    |> Map.put(:context, root_query.__ash_bindings__.context)
    |> Ash.Query.set_context(relationship.context)
    |> Ash.Query.do_filter(relationship.filter)
    |> Ash.Query.sort(Map.get(relationship, :sort))
    |> case do
      %{valid?: true} = query ->
        initial_query = %{
          AshPostgres.DataLayer.resource_to_query(resource, nil)
          | prefix: Map.get(root_query, :prefix)
        }

        Ash.Query.data_layer_query(query,
          only_validate_filter?: false,
          initial_query: initial_query
        )

      query ->
        {:error, query}
    end
  end

  def set_join_prefix(join_query, query, resource) do
    if Ash.Resource.Info.multitenancy_strategy(resource) == :context do
      %{join_query | prefix: query.prefix || "public"}
    else
      %{
        join_query
        | prefix: AshPostgres.repo(resource).config()[:default_prefix] || "public"
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
      from(row in joined_query,
        distinct: ^Ash.Resource.Info.primary_key(relationship.destination)
      )
    else
      joined_query
    end
  end

  defp join_relationship(query, relationship, path, join_type, source, filter) do
    case Map.get(query.__ash_bindings__.bindings, path) do
      %{type: existing_join_type} when join_type != existing_join_type ->
        raise "unreachable?"

      nil ->
        do_join_relationship(query, relationship, path, join_type, source, filter)

      _ ->
        {:ok, query}
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
    join_relationship = Ash.Resource.Info.relationship(source, relationship.join_relationship)

    with {:ok, relationship_through} <-
           maybe_get_resource_query(relationship.through, join_relationship, query),
         {:ok, relationship_destination} <-
           maybe_get_resource_query(relationship.destination, relationship, query) do
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
        Enum.find_value(query.__ash_bindings__.bindings, 0, fn {binding, data} ->
          if data.type == binding_kind && data.path == Enum.reverse(path) do
            binding
          end
        end)

      used_calculations =
        Ash.Filter.used_calculations(
          filter,
          relationship.destination,
          path ++ [relationship.name]
        )

      used_aggregates =
        AshPostgres.Aggregate.used_aggregates(filter, relationship, used_calculations, path)

      Enum.reduce_while(used_aggregates, {:ok, relationship_destination}, fn agg, {:ok, query} ->
        agg = %{agg | load: agg.name}

        case AshPostgres.Aggregate.add_aggregates(query, [agg], relationship.destination) do
          {:ok, query} ->
            {:cont, {:ok, query}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, relationship_destination} ->
          relationship_destination =
            case used_aggregates do
              [] ->
                relationship_destination

              _ ->
                subquery(relationship_destination)
            end

          new_query =
            case kind do
              {:aggregate, _, subquery} ->
                subquery =
                  AshPostgres.Aggregate.agg_subquery_for_lateral_join(
                    current_binding,
                    query,
                    subquery,
                    relationship
                  )

                from([{row, current_binding}] in query,
                  left_lateral_join: through in ^subquery,
                  as: query.__ash_bindings__.current
                )

              :inner ->
                from([{row, current_binding}] in query,
                  join: through in ^relationship_through,
                  as: query.__ash_bindings__.current,
                  on:
                    field(row, ^relationship.source_field) ==
                      field(through, ^relationship.source_field_on_join_table),
                  join: destination in ^relationship_destination,
                  as: query.__ash_bindings__.current + 1,
                  on:
                    field(destination, ^relationship.destination_field) ==
                      field(through, ^relationship.destination_field_on_join_table)
                )

              _ ->
                from([{row, current_binding}] in query,
                  left_join: through in ^relationship_through,
                  as: query.__ash_bindings__.current,
                  on:
                    field(row, ^relationship.source_field) ==
                      field(through, ^relationship.source_field_on_join_table),
                  left_join: destination in ^relationship_destination,
                  as: query.__ash_bindings__.current + 1,
                  on:
                    field(destination, ^relationship.destination_field) ==
                      field(through, ^relationship.destination_field_on_join_table)
                )
            end

          join_path =
            Enum.reverse([
              String.to_existing_atom(to_string(relationship.name) <> "_join_assoc") | path
            ])

          full_path = Enum.reverse([relationship.name | path])

          binding_data =
            case kind do
              {:aggregate, name, _agg} ->
                %{type: :aggregate, name: name, path: full_path, source: source}

              _ ->
                %{type: kind, path: full_path, source: source}
            end

          case kind do
            {:aggregate, _, _subquery} ->
              {:ok,
               new_query
               |> AshPostgres.DataLayer.add_binding(binding_data)}

            _ ->
              {:ok,
               new_query
               |> AshPostgres.DataLayer.add_binding(%{
                 path: join_path,
                 type: :left,
                 source: source
               })
               |> AshPostgres.DataLayer.add_binding(binding_data)}
          end

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp do_join_relationship(query, relationship, path, kind, source, filter) do
    case maybe_get_resource_query(relationship.destination, relationship, query) do
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
          Enum.find_value(query.__ash_bindings__.bindings, 0, fn {binding, data} ->
            if data.type == binding_kind && data.path == Enum.reverse(path) do
              binding
            end
          end)

        used_calculations =
          Ash.Filter.used_calculations(
            filter,
            relationship.destination,
            path ++ [relationship.name]
          )

        used_aggregates =
          AshPostgres.Aggregate.used_aggregates(filter, relationship, used_calculations, path)

        Enum.reduce_while(used_aggregates, {:ok, relationship_destination}, fn agg,
                                                                               {:ok, query} ->
          agg = %{agg | load: agg.name}

          case AshPostgres.Aggregate.add_aggregates(query, [agg], relationship.destination) do
            {:ok, query} ->
              {:cont, {:ok, query}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
        end)
        |> case do
          {:ok, relationship_destination} ->
            relationship_destination =
              case used_aggregates do
                [] ->
                  relationship_destination

                _ ->
                  subquery(relationship_destination)
              end

            new_query =
              case kind do
                {:aggregate, _, subquery} ->
                  subquery =
                    AshPostgres.Aggregate.agg_subquery_for_lateral_join(
                      current_binding,
                      query,
                      subquery,
                      relationship
                    )

                  from([{row, current_binding}] in query,
                    left_lateral_join: destination in ^subquery,
                    as: query.__ash_bindings__.current,
                    on:
                      field(row, ^relationship.source_field) ==
                        field(destination, ^relationship.destination_field)
                  )

                :inner ->
                  from([{row, current_binding}] in query,
                    join: destination in ^relationship_destination,
                    as: query.__ash_bindings__.current,
                    on:
                      field(row, ^relationship.source_field) ==
                        field(destination, ^relationship.destination_field)
                  )

                _ ->
                  from([{row, current_binding}] in query,
                    left_join: destination in ^relationship_destination,
                    as: query.__ash_bindings__.current,
                    on:
                      field(row, ^relationship.source_field) ==
                        field(destination, ^relationship.destination_field)
                  )
              end

            full_path = Enum.reverse([relationship.name | path])

            binding_data =
              case kind do
                {:aggregate, name, _agg} ->
                  %{type: :aggregate, name: name, path: full_path, source: source}

                _ ->
                  %{type: kind, path: full_path, source: source}
              end

            {:ok,
             new_query
             |> AshPostgres.DataLayer.add_binding(binding_data)}

          {:error, error} ->
            {:error, error}
        end
    end
  end
end
