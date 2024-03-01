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
        sort? \\ true,
        join_filters \\ nil,
        parent_bindings \\ nil,
        no_inner_join? \\ false
      )

  # simple optimization for common cases
  def join_all_relationships(
        query,
        filter,
        _opts,
        relationship_paths,
        _path,
        _source,
        _sort?,
        _join_filters,
        _parent_bindings,
        _no_inner_join?
      )
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
        sort?,
        join_filters,
        parent_query,
        no_inner_join?
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
        join_type =
          if no_inner_join? do
            :left
          else
            join_type
          end

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

        binding =
          get_binding(source, Enum.map(current_path, & &1.name), query, look_for_join_types)

        # We can't reuse joins if we're adding filters/have a separate parent binding
        if is_nil(join_filters) && is_nil(parent_query) && binding do
          case join_all_relationships(
                 query,
                 filter,
                 opts,
                 [{join_type, rest_rels}],
                 current_path,
                 source,
                 sort?
               ) do
            {:ok, query} ->
              {:cont, {:ok, query}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
        else
          case join_relationship(
                 set_parent_bindings(query, parent_query),
                 relationship,
                 Enum.map(path, & &1.name),
                 current_join_type,
                 source,
                 filter,
                 sort?,
                 Ash.Filter.move_to_relationship_path(
                   join_filters[Enum.map(current_path, & &1.name)],
                   [relationship.name]
                 )
               ) do
            {:ok, joined_query} ->
              joined_query_with_distinct = add_distinct(relationship, join_type, joined_query)

              case join_all_relationships(
                     joined_query_with_distinct,
                     filter,
                     opts,
                     [{join_type, rest_rels}],
                     current_path,
                     source,
                     sort?,
                     join_filters,
                     joined_query
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

  defp set_parent_bindings(query, parent_query) do
    if parent_query do
      AshPostgres.Expr.set_parent_path(query, parent_query, false)
    else
      query
    end
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

  def relationship_path_to_relationships(resource, path, acc \\ [])
  def relationship_path_to_relationships(_resource, [], acc), do: Enum.reverse(acc)

  def relationship_path_to_relationships(resource, [name | rest], acc) do
    relationship = Ash.Resource.Info.relationship(resource, name)

    if !relationship do
      raise "no such relationship #{inspect(resource)}.#{name}"
    end

    relationship_path_to_relationships(relationship.destination, rest, [relationship | acc])
  end

  def related_subquery(
        relationship,
        root_query,
        opts \\ []
      ) do
    on_parent_expr = Keyword.get(opts, :on_parent_expr, & &1)
    on_subquery = Keyword.get(opts, :on_subquery, & &1)

    with {:ok, query} <- related_query(relationship, root_query, opts) do
      has_parent_expr? =
        !!query.__ash_bindings__.context[:data_layer][:has_parent_expr?] ||
          not is_nil(query.limit)

      query =
        if has_parent_expr? do
          on_parent_expr.(query)
        else
          query
        end

      query = on_subquery.(query)

      query =
        if opts[:return_subquery?] do
          subquery(query)
        else
          if Enum.empty?(query.joins) && Enum.empty?(query.order_bys) && Enum.empty?(query.wheres) do
            query
          else
            from(row in subquery(query), as: ^0)
            |> AshPostgres.DataLayer.default_bindings(relationship.destination)
            |> AshPostgres.DataLayer.merge_expr_accumulator(
              query.__ash_bindings__.expression_accumulator
            )
            |> Map.update!(
              :__ash_bindings__,
              fn bindings ->
                bindings
                |> Map.put(:current, query.__ash_bindings__.current)
                |> put_in([:context, :data_layer], %{
                  has_parent_expr?: has_parent_expr?
                })
              end
            )
          end
        end

      {:ok, query}
    end
  end

  defp related_query(relationship, query, opts) do
    sort? = Keyword.get(opts, :sort?, false)
    filter = Keyword.get(opts, :filter, nil)
    parent_resources = Keyword.get(opts, :parent_stack, [relationship.source])

    read_action =
      relationship.read_action ||
        Ash.Resource.Info.primary_action!(relationship.destination, :read).name

    context = query.__ash_bindings__.context

    relationship.destination
    |> Ash.Query.new()
    |> Ash.Query.set_context(context)
    |> Ash.Query.set_context(%{data_layer: %{table: nil}})
    |> Ash.Query.set_context(relationship.context)
    |> Ash.Query.do_filter(relationship.filter, parent_stack: parent_resources)
    |> Ash.Query.do_filter(filter, parent_stack: parent_resources)
    |> Ash.Query.for_read(read_action, %{},
      actor: context[:private][:actor],
      tenant: context[:private][:tenant]
    )
    |> Ash.Query.unset([:sort, :distinct, :select, :limit, :offset])
    |> limit_from_many(relationship)
    |> then(fn query ->
      if sort? do
        Ash.Query.sort(query, relationship.sort)
      else
        Ash.Query.unset(query, :sort)
      end
    end)
    |> set_has_parent_expr_context(relationship)
    |> case do
      %{valid?: true} = related_query ->
        Ash.Query.data_layer_query(
          Ash.Query.set_context(related_query, %{
            data_layer: %{parent_bindings: query.__ash_bindings__}
          })
        )
        |> case do
          {:ok, ecto_query} ->
            {:ok,
             ecto_query
             |> set_join_prefix(query, relationship.destination)
             |> Ecto.Query.exclude(:select)}

          {:error, error} ->
            {:error, error}
        end

      %{errors: errors} ->
        {:error, errors}
    end
  end

  defp limit_from_many(query, %{from_many?: true}) do
    Ash.Query.limit(query, 1)
  end

  defp limit_from_many(query, _), do: query

  defp set_has_parent_expr_context(query, relationship) do
    has_parent_expr? =
      Ash.Actions.Read.Relationships.has_parent_expr?(%{
        relationship
        | filter: query.filter,
          sort: query.sort
      })

    Ash.Query.set_context(query, %{data_layer: %{has_parent_expr?: has_parent_expr?}})
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
         relationship.cardinality == :many &&
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
         %{manual: {module, opts}} = relationship,
         path,
         kind,
         source,
         filter,
         sort?,
         apply_filter
       ) do
    full_path = path ++ [relationship.name]
    initial_ash_bindings = query.__ash_bindings__

    binding_data = %{type: kind, path: full_path, source: source}

    query = AshPostgres.DataLayer.add_binding(query, binding_data)

    used_aggregates = Ash.Filter.used_aggregates(filter, full_path)

    with {:ok, relationship_destination} <-
           related_subquery(relationship, query, sort?: sort?) do
      {relationship_destination, acc} =
        maybe_apply_filter(relationship_destination, query, query.__ash_bindings__, apply_filter)

      query = AshPostgres.DataLayer.merge_expr_accumulator(query, acc)

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

        {:error, query} ->
          {:error, query}
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

  defp join_relationship(
         query,
         %{type: :many_to_many} = relationship,
         path,
         kind,
         source,
         filter,
         sort?,
         apply_filter
       ) do
    join_relationship =
      Ash.Resource.Info.relationship(relationship.source, relationship.join_relationship)

    join_path = path ++ [join_relationship.name]

    full_path = path ++ [relationship.name]

    initial_ash_bindings = query.__ash_bindings__

    binding_data = %{type: kind, path: full_path, source: source}

    used_aggregates = Ash.Filter.used_aggregates(filter, full_path)

    query =
      query
      |> AshPostgres.DataLayer.add_binding(%{
        path: join_path,
        type: :left,
        source: source
      })
      |> AshPostgres.DataLayer.add_binding(binding_data)

    with {:ok, relationship_through} <- related_subquery(join_relationship, query),
         {:ok, relationship_destination} <-
           related_subquery(relationship, query, sort?: sort?) do
      {relationship_destination, dest_acc} =
        maybe_apply_filter(relationship_destination, query, query.__ash_bindings__, apply_filter)

      query =
        query
        |> AshPostgres.DataLayer.merge_expr_accumulator(dest_acc)

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

      query =
        case kind do
          :inner ->
            from(_ in query,
              join: through in ^relationship_through,
              as: ^initial_ash_bindings.current,
              on:
                field(as(^current_binding), ^relationship.source_attribute) ==
                  field(through, ^relationship.source_attribute_on_join_resource),
              join: destination in ^relationship_destination,
              as: ^(initial_ash_bindings.current + 1),
              on:
                field(destination, ^relationship.destination_attribute) ==
                  field(through, ^relationship.destination_attribute_on_join_resource)
            )

          _ ->
            from(_ in query,
              left_join: through in ^relationship_through,
              as: ^initial_ash_bindings.current,
              on:
                field(as(^current_binding), ^relationship.source_attribute) ==
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

  defp join_relationship(
         query,
         relationship,
         path,
         kind,
         source,
         filter,
         sort?,
         apply_filter
       ) do
    full_path = path ++ [relationship.name]
    initial_ash_bindings = query.__ash_bindings__

    binding_data = %{type: kind, path: full_path, source: source}

    query = AshPostgres.DataLayer.add_binding(query, binding_data)

    used_aggregates = Ash.Filter.used_aggregates(filter, full_path)

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

    case related_subquery(relationship, query,
           sort?: sort?,
           on_parent_expr: fn subquery ->
             if Map.get(relationship, :no_attributes?) do
               subquery
             else
               from(row in subquery,
                 where:
                   field(parent_as(^current_binding), ^relationship.source_attribute) ==
                     field(
                       row,
                       ^relationship.destination_attribute
                     )
               )
             end
           end
         ) do
      {:error, error} ->
        {:error, error}

      {:ok, relationship_destination} ->
        {relationship_destination, acc} =
          maybe_apply_filter(
            relationship_destination,
            query,
            query.__ash_bindings__,
            apply_filter
          )

        query = AshPostgres.DataLayer.merge_expr_accumulator(query, acc)

        query =
          case {kind, Map.get(relationship, :no_attributes?, false),
                relationship_destination.__ash_bindings__.context[:data_layer][
                  :has_parent_expr?
                ]} do
            {:inner, true, false} ->
              from(_ in query,
                join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
              )

            {:inner, true, true} ->
              from(_ in query,
                inner_lateral_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
              )

            {:inner, false, false} ->
              from(_ in query,
                join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on:
                  field(as(^current_binding), ^relationship.source_attribute) ==
                    field(
                      destination,
                      ^relationship.destination_attribute
                    )
              )

            {:inner, false, true} ->
              from(_ in query,
                inner_lateral_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
              )

            {:left, true, false} ->
              from(_ in query,
                left_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
              )

            {:left, true, true} ->
              from(_ in query,
                left_lateral_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
              )

            {:left, false, false} ->
              from(_ in query,
                left_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on:
                  field(as(^current_binding), ^relationship.source_attribute) ==
                    field(
                      destination,
                      ^relationship.destination_attribute
                    )
              )

            {:left, false, true} ->
              from(_ in query,
                left_lateral_join: destination in ^relationship_destination,
                as: ^initial_ash_bindings.current,
                on: true
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

  @doc false
  def maybe_apply_filter(query, _root_query, _bindings, nil),
    do: {query, %AshPostgres.Expr.ExprInfo{}}

  def maybe_apply_filter(query, root_query, bindings, filter) do
    {dynamic, acc} = AshPostgres.Expr.dynamic_expr(root_query, filter, bindings, true)
    {from(row in query, where: ^dynamic), acc}
  end
end
