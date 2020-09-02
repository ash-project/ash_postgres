defmodule AshPostgres.DataLayer do
  @moduledoc """
  A postgres data layer that levereges Ecto's postgres capabilities.

  To use this data layer, you need to define an `Ecto.Repo`. Ash adds some
  functionality on top of ecto repos, so you'll want to use `AshPostgres.Repo`

  Then, configure your resource like so:

  ```
  postgres do
    repo MyApp.Repo
    table "table_name"
  end
  ```
  """
  @postgres %Ash.Dsl.Section{
    name: :postgres,
    describe: """
    Postgres data layer configuration
    """,
    schema: [
      repo: [
        type: {:custom, AshPostgres.DataLayer, :validate_repo, []},
        required: true,
        doc:
          "The repo that will be used to fetch your data. See the `Ecto.Repo` documentation for more"
      ],
      table: [
        type: :string,
        required: true,
        doc: "The table to store and read the resource from"
      ]
    ]
  }

  alias Ash.DataLayer.Delegate
  alias Ash.Filter
  alias Ash.Filter.{Expression, Not, Predicate}
  alias Ash.Filter.Predicate.{Eq, GreaterThan, In, IsNil, LessThan}
  alias AshPostgres.Predicates.Trigram

  import AshPostgres, only: [table: 1, repo: 1]

  @behaviour Ash.DataLayer

  use Ash.Dsl.Extension, sections: [@postgres]

  @doc false
  def validate_repo(repo) do
    if repo.__adapter__() == Ecto.Adapters.Postgres do
      {:ok, repo}
    else
      {:error, "Expected a repo using the postgres adapter `Ecto.Adapters.Postgres`"}
    end
  end

  @impl true
  def custom_filters(resource) do
    config = repo(resource).config()

    add_pg_trgm_search(%{}, config)
  end

  defp add_pg_trgm_search(filters, config) do
    if "pg_trgm" in (config[:installed_extensions] || []) do
      Map.update(filters, :string, [{:trigram, AshPostgres.Predicates.Trigram}], fn filters ->
        [{:trigram, AshPostgres.Predicates.Trigram} | filters]
      end)
    else
      filters
    end
  end

  import Ecto.Query, only: [from: 2, subquery: 1]

  @impl true
  def can?(_, :async_engine), do: true
  def can?(_, :transact), do: true
  def can?(_, :composite_primary_key), do: true
  def can?(_, :upsert), do: true

  def can?(resource, {:join, other_resource}) do
    other_resource = Delegate.get_delegated(other_resource)
    data_layer = Ash.Resource.data_layer(resource)
    other_data_layer = Ash.Resource.data_layer(other_resource)
    data_layer == other_data_layer and repo(data_layer) == repo(other_data_layer)
  end

  def can?(resource, {:lateral_join, other_resource}) do
    other_resource = Delegate.get_delegated(other_resource)
    data_layer = Ash.Resource.data_layer(resource)
    other_data_layer = Ash.Resource.data_layer(other_resource)
    data_layer == other_data_layer and repo(data_layer) == repo(other_data_layer)
  end

  def can?(_, :boolean_filter), do: true
  def can?(_, {:aggregate, :count}), do: true
  def can?(_, :aggregate_filter), do: true
  def can?(_, :aggregate_sort), do: true
  def can?(_, :create), do: true
  def can?(_, :read), do: true
  def can?(_, :update), do: true
  def can?(_, :destroy), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  def can?(_, :offset), do: true
  def can?(_, {:filter_predicate, _, %In{}}), do: true
  def can?(_, {:filter_predicate, _, %Eq{}}), do: true
  def can?(_, {:filter_predicate, _, %LessThan{}}), do: true
  def can?(_, {:filter_predicate, _, %GreaterThan{}}), do: true
  def can?(_, {:filter_predicate, _, %IsNil{}}), do: true
  def can?(_, {:filter_predicate, :string, %Trigram{}}), do: true
  def can?(_, {:filter_predicate, _}), do: false
  def can?(_, :sort), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, _), do: false

  @impl true
  def in_transaction?(resource) do
    repo(resource).in_transaction?()
  end

  @impl true
  def limit(query, nil, _), do: {:ok, query}

  def limit(query, limit, _resource) do
    {:ok, from(row in query, limit: ^limit)}
  end

  @impl true
  def source(resource) do
    table(resource)
  end

  @impl true
  def offset(query, nil, _), do: query

  def offset(query, offset, _resource) do
    {:ok, from(row in query, offset: ^offset)}
  end

  @impl true
  def run_query(query, resource) do
    {:ok, repo(resource).all(query)}
  end

  @impl true
  def run_query_with_lateral_join(
        query,
        root_data,
        source_resource,
        _destination_resource,
        source_field,
        destination_field
      ) do
    source_values = Enum.map(root_data, &Map.get(&1, source_field))

    subquery =
      subquery(
        from(destination in query,
          where:
            field(destination, ^destination_field) ==
              field(parent_as(:source_record), ^source_field)
        )
      )

    query =
      from(source in resource_to_query(source_resource),
        as: :source_record,
        where: field(source, ^source_field) in ^source_values,
        inner_lateral_join: destination in ^subquery,
        on: field(source, ^source_field) == field(destination, ^destination_field),
        select: destination
      )

    {:ok, repo(source_resource).all(query)}
  end

  @impl true
  def resource_to_query(resource),
    do: Ecto.Queryable.to_query({table(resource), resource})

  @impl true
  def create(resource, changeset) do
    changeset.data
    |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource)))
    |> ecto_changeset(changeset)
    |> repo(resource).insert()
  rescue
    e ->
      {:error, e}
  end

  defp ecto_changeset(record, changeset) do
    Ecto.Changeset.change(record, changeset.attributes)
  end

  @impl true
  def upsert(resource, changeset) do
    changeset.data
    |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource)))
    |> ecto_changeset(changeset)
    |> repo(resource).insert(
      on_conflict: :replace_all,
      conflict_target: Ash.Resource.primary_key(resource)
    )
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def update(resource, changeset) do
    changeset.data
    |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource)))
    |> ecto_changeset(changeset)
    |> repo(resource).update()
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def destroy(resource, %{data: record}) do
    case repo(resource).delete(record) do
      {:ok, _record} -> :ok
      {:error, error} -> {:error, error}
    end
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def sort(query, sort, resource) do
    query = default_bindings(query, resource)

    sort
    |> sanitize_sort()
    |> Enum.reduce({:ok, query}, fn {order, sort}, query ->
      binding =
        case Map.fetch(query.__ash_bindings__.aggregates, sort) do
          {:ok, binding} ->
            binding

          :error ->
            0
        end

      {:ok,
       from([{^binding, row}] in query,
         order_by: [{^order, field(row, ^sort)}]
       )}
    end)
  end

  defp sanitize_sort(sort) do
    sort
    |> List.wrap()
    |> Enum.map(fn
      {sort, order} -> {order, sort}
      sort -> sort
    end)
  end

  @impl true
  def filter(query, %{expression: false}, _resource) do
    impossible_query = from(row in query, where: false)
    {:ok, Map.put(impossible_query, :__impossible__, true)}
  end

  def filter(query, filter, _resource) do
    relationship_paths =
      filter
      |> Filter.relationship_paths()
      |> Enum.map(fn path ->
        if can_inner_join?(path, filter) do
          {:inner, relationship_path_to_relationships(filter.resource, path)}
        else
          {:left, relationship_path_to_relationships(filter.resource, path)}
        end
      end)

    new_query =
      query
      |> join_all_relationships(relationship_paths)
      |> add_filter_expression(filter)

    {:ok, new_query}
  end

  defp default_bindings(query, resource) do
    Map.put_new(query, :__ash_bindings__, %{
      current: Enum.count(query.joins) + 1,
      aggregates: %{},
      bindings: %{0 => %{path: [], type: :root, source: resource}}
    })
  end

  defp can_inner_join?(path, expr, seen_an_or? \\ false)

  defp can_inner_join?(path, %{expression: expr}, seen_an_or?),
    do: can_inner_join?(path, expr, seen_an_or?)

  defp can_inner_join?(_path, expr, _seen_an_or?) when expr in [nil, true, false], do: true

  defp can_inner_join?(path, %Expression{op: :and, left: left, right: right}, seen_an_or?) do
    can_inner_join?(path, left, seen_an_or?) || can_inner_join?(path, right, seen_an_or?)
  end

  defp can_inner_join?(path, %Expression{op: :or, left: left, right: right}, _) do
    can_inner_join?(path, left, true) && can_inner_join?(path, right, true)
  end

  defp can_inner_join?(
         path,
         %Not{expression: %Expression{op: :or, left: left, right: right}},
         seen_an_or?
       ) do
    can_inner_join?(
      path,
      %Expression{
        op: :and,
        left: %Not{expression: left},
        right: %Not{expression: right}
      },
      seen_an_or?
    )
  end

  defp can_inner_join?(path, %Not{expression: expression}, seen_an_or?) do
    can_inner_join?(path, expression, seen_an_or?)
  end

  defp can_inner_join?(_path, %Predicate{predicate: %IsNil{nil?: true}}, seen_an_or?),
    do: not seen_an_or?

  defp can_inner_join?(search_path, %Predicate{relationship_path: relationship_path}, seen_an_or?)
       when search_path == relationship_path do
    not seen_an_or?
  end

  defp can_inner_join?(_, _, _), do: true

  @impl true
  def add_aggregate(query, aggregate, _resource) do
    resource = aggregate.resource
    query = default_bindings(query, resource)

    {query, binding} =
      case get_binding(resource, aggregate.relationship_path, query, :aggregate) do
        nil ->
          relationship = Ash.Resource.relationship(resource, aggregate.relationship_path)
          subquery = aggregate_subquery(relationship, aggregate)

          new_query =
            join_all_relationships(
              query,
              [
                {{:aggregate, aggregate.name, subquery},
                 relationship_path_to_relationships(resource, aggregate.relationship_path)}
              ]
            )

          {new_query, get_binding(resource, aggregate.relationship_path, new_query, :aggregate)}

        binding ->
          {query, binding}
      end

    query_with_aggregate_binding =
      put_in(
        query.__ash_bindings__.aggregates,
        Map.put(query.__ash_bindings__.aggregates, aggregate.name, binding)
      )

    new_query =
      query_with_aggregate_binding
      |> add_aggregate_to_subquery(resource, aggregate, binding)
      |> select_aggregate(resource, aggregate)

    {:ok, new_query}
  end

  defp select_aggregate(query, resource, aggregate) do
    binding = get_binding(resource, aggregate.relationship_path, query, :aggregate)

    query =
      if query.select do
        query
      else
        from(row in query,
          select: row,
          select_merge: %{aggregates: %{}}
        )
      end

    %{query | select: add_to_select(query.select, binding, aggregate)}
  end

  defp add_to_select(
         %{expr: {:merge, _, [first, {:%{}, _, [{:aggregates, {:%{}, [], fields}}]}]}} = select,
         binding,
         %{load: nil} = aggregate
       ) do
    field =
      {:type, [],
       [
         {{:., [], [{:&, [], [binding]}, aggregate.name]}, [], []},
         Ash.Type.ecto_type(aggregate.type)
       ]}

    field_with_default =
      if aggregate.default_value do
        {:coalesce, [],
         [
           field,
           aggregate.default_value
         ]}
      end

    new_fields = [
      {aggregate.name, field_with_default}
      | fields
    ]

    %{select | expr: {:merge, [], [first, {:%{}, [], [{:aggregates, {:%{}, [], new_fields}}]}]}}
  end

  defp add_to_select(
         %{expr: expr} = select,
         binding,
         %{load: load_as} = aggregate
       ) do
    field =
      {:type, [],
       [
         {{:., [], [{:&, [], [binding]}, aggregate.name]}, [], []},
         Ash.Type.ecto_type(aggregate.type)
       ]}

    field_with_default =
      if aggregate.default_value do
        {:coalesce, [],
         [
           field,
           aggregate.default_value
         ]}
      end

    %{select | expr: {:merge, [], [expr, {:%{}, [], [{load_as, field_with_default}]}]}}
  end

  defp add_aggregate_to_subquery(query, resource, aggregate, binding) do
    new_joins =
      List.update_at(query.joins, binding - 1, fn join ->
        aggregate_query =
          if aggregate.authorization_filter do
            {:ok, filter} =
              filter(
                join.source.from.source.query,
                aggregate.authorization_filter,
                Ash.Resource.related(resource, aggregate.relationship_path)
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

  defp aggregate_subquery(relationship, _aggregate) do
    from(row in relationship.destination,
      group_by: ^relationship.destination_field,
      select: field(row, ^relationship.destination_field)
    )
  end

  defp add_subquery_aggregate_select(query, %{kind: :count} = aggregate, resource) do
    query = default_bindings(query, aggregate.resource)
    key_to_count = List.first(Ash.Resource.primary_key(resource))
    type = Ash.Type.ecto_type(aggregate.type)

    field = {:count, [], [{{:., [], [{:&, [], [0]}, key_to_count]}, [], []}]}

    {params, filtered} =
      if aggregate.query do
        {params, expr} =
          filter_to_expr(
            aggregate.query.filter,
            query.__ash_bindings__.bindings,
            query.select.params
          )

        {params, {:filter, [], [field, expr]}}
      else
        {[], field}
      end

    cast = {:type, [], [filtered, type]}

    new_expr = {:merge, [], [query.select.expr, {:%{}, [], [{aggregate.name, cast}]}]}

    %{query | select: %{query.select | expr: new_expr, params: params}}
  end

  defp relationship_path_to_relationships(resource, path, acc \\ [])
  defp relationship_path_to_relationships(_resource, [], acc), do: Enum.reverse(acc)

  defp relationship_path_to_relationships(resource, [relationship | rest], acc) do
    relationship = Ash.Resource.relationship(resource, relationship)

    relationship_path_to_relationships(relationship.destination, rest, [relationship | acc])
  end

  defp join_all_relationships(query, relationship_paths, path \\ [], source \\ nil) do
    query = default_bindings(query, source)

    Enum.reduce(relationship_paths, query, fn
      {_join_type, []}, query ->
        query

      {join_type, [relationship | rest_rels]}, query ->
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
          query
        else
          joined_query =
            join_relationship(
              query,
              relationship,
              Enum.map(path, & &1.name),
              current_join_type,
              source
            )

          joined_query_with_distinct = add_distinct(relationship, join_type, joined_query)

          join_all_relationships(
            joined_query_with_distinct,
            [{join_type, rest_rels}],
            current_path,
            source
          )
        end
    end)
  end

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

  defp get_binding(resource, path, %{__ash_bindings__: _} = query, type) do
    paths =
      Enum.flat_map(query.__ash_bindings__.bindings, fn
        {binding, %{path: path, type: ^type}} ->
          [{binding, path}]

        _ ->
          []
      end)

    Enum.find_value(paths, fn {binding, candidate_path} ->
      Ash.SatSolver.synonymous_relationship_paths?(resource, candidate_path, path) && binding
    end)
  end

  defp get_binding(_, _, _, _), do: nil

  defp add_distinct(relationship, join_type, joined_query) do
    if relationship.cardinality == :many and join_type == :left && !joined_query.distinct do
      from(row in joined_query,
        distinct: ^Ash.Resource.primary_key(relationship.destination)
      )
    else
      joined_query
    end
  end

  defp join_relationship(query, relationship, path, join_type, source) do
    case Map.get(query.__ash_bindings__.bindings, path) do
      %{type: existing_join_type} when join_type != existing_join_type ->
        raise "unreachable?"

      nil ->
        do_join_relationship(query, relationship, path, join_type, source)

      _ ->
        query
    end
  end

  defp do_join_relationship(query, %{type: :many_to_many} = relationship, path, kind, source) do
    relationship_through = maybe_get_resource_query(relationship.through)

    relationship_destination =
      Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    current_binding =
      Enum.find_value(query.__ash_bindings__.bindings, 0, fn {binding, data} ->
        if data.type == kind && data.path == Enum.reverse(path) do
          binding
        end
      end)

    new_query =
      case kind do
        {:aggregate, _, subquery} ->
          subquery =
            subquery(
              from(destination in subquery,
                where:
                  field(destination, ^relationship.destination_field) ==
                    field(
                      parent_as(:rel_through),
                      ^relationship.destination_field_on_join_table
                    )
              )
            )

          from([{row, current_binding}] in query,
            left_join: through in ^relationship_through,
            as: :rel_through,
            on:
              field(row, ^relationship.source_field) ==
                field(through, ^relationship.source_field_on_join_table),
            left_lateral_join: destination in ^subquery,
            on:
              field(destination, ^relationship.destination_field) ==
                field(through, ^relationship.destination_field_on_join_table)
          )

        :inner ->
          from([{row, current_binding}] in query,
            join: through in ^relationship_through,
            on:
              field(row, ^relationship.source_field) ==
                field(through, ^relationship.source_field_on_join_table),
            join: destination in ^relationship_destination,
            on:
              field(destination, ^relationship.destination_field) ==
                field(through, ^relationship.destination_field_on_join_table)
          )

        _ ->
          from([{row, current_binding}] in query,
            left_join: through in ^relationship_through,
            on:
              field(row, ^relationship.source_field) ==
                field(through, ^relationship.source_field_on_join_table),
            left_join: destination in ^relationship_destination,
            on:
              field(destination, ^relationship.destination_field) ==
                field(through, ^relationship.destination_field_on_join_table)
          )
      end

    join_path =
      Enum.reverse([String.to_existing_atom(to_string(relationship.name) <> "_join_assoc") | path])

    full_path = Enum.reverse([relationship.name | path])

    binding_data =
      case kind do
        {:aggregate, name, _agg} ->
          %{type: :aggregate, name: name, path: full_path, source: source}

        _ ->
          %{type: kind, path: full_path, source: source}
      end

    new_query
    |> add_binding(%{path: join_path, type: :left, source: source})
    |> add_binding(binding_data)
  end

  defp do_join_relationship(query, relationship, path, kind, source) do
    relationship_destination =
      Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    current_binding =
      Enum.find_value(query.__ash_bindings__.bindings, 0, fn {binding, data} ->
        if data.type == kind && data.path == Enum.reverse(path) do
          binding
        end
      end)

    new_query =
      case kind do
        {:aggregate, _, subquery} ->
          subquery =
            from(
              sub in subquery(
                from(destination in subquery,
                  where:
                    field(destination, ^relationship.destination_field) ==
                      field(parent_as(:rel_source), ^relationship.source_field)
                )
              ),
              select: field(sub, ^relationship.destination_field)
            )

          from([{row, current_binding}] in query,
            as: :rel_source,
            left_lateral_join: destination in ^subquery,
            on:
              field(row, ^relationship.source_field) ==
                field(destination, ^relationship.destination_field)
          )

        :inner ->
          from([{row, current_binding}] in query,
            join: destination in ^relationship_destination,
            on:
              field(row, ^relationship.source_field) ==
                field(destination, ^relationship.destination_field)
          )

        _ ->
          from([{row, current_binding}] in query,
            left_join: destination in ^relationship_destination,
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

    new_query
    |> add_binding(binding_data)
  end

  defp add_filter_expression(query, filter) do
    filter
    |> split_and_statements()
    |> Enum.reduce(query, fn filter, query ->
      clause = filter_to_dynamic_expr(filter, query.__ash_bindings__.bindings)

      from(row in query,
        where: ^clause
      )
    end)
  end

  defp split_and_statements(%Filter{expression: expression}) do
    split_and_statements(expression)
  end

  defp split_and_statements(%Expression{op: :and, left: left, right: right}) do
    split_and_statements(left) ++ split_and_statements(right)
  end

  defp split_and_statements(%Not{expression: %Not{expression: expression}}) do
    split_and_statements(expression)
  end

  defp split_and_statements(%Not{expression: %Expression{op: :or, left: left, right: right}}) do
    split_and_statements(%Expression{
      op: :and,
      left: %Not{expression: left},
      right: %Not{expression: right}
    })
  end

  defp split_and_statements(other), do: [other]

  defp filter_to_dynamic_expr(%Filter{expression: expression}, bindings) do
    filter_to_dynamic_expr(expression, bindings)
  end

  defp filter_to_dynamic_expr(nil, _), do: true
  defp filter_to_dynamic_expr(true, _), do: true
  defp filter_to_dynamic_expr(false, _), do: false

  defp filter_to_dynamic_expr(%Expression{op: :and, left: left, right: right}, bindings) do
    left = filter_to_dynamic_expr(left, bindings)
    right = filter_to_dynamic_expr(right, bindings)
    Ecto.Query.dynamic([row], ^left and ^right)
  end

  defp filter_to_dynamic_expr(%Expression{op: :or, left: left, right: right}, bindings) do
    left = filter_to_dynamic_expr(left, bindings)
    right = filter_to_dynamic_expr(right, bindings)
    Ecto.Query.dynamic([row], ^left or ^right)
  end

  defp filter_to_dynamic_expr(%Not{expression: expression}, bindings) do
    expression = filter_to_dynamic_expr(expression, bindings)

    Ecto.Query.dynamic([row], not (^expression))
  end

  defp filter_to_dynamic_expr(%Predicate{} = pred, bindings) do
    %{predicate: predicate, relationship_path: relationship_path, attribute: attribute} = pred

    current_binding =
      case attribute do
        %Ash.Resource.Attribute{} ->
          Enum.find_value(bindings, fn {binding, data} ->
            data.path == relationship_path && data.type in [:left, :inner, :root] && binding
          end)

        %Ash.Query.Aggregate{} = aggregate ->
          Enum.find_value(bindings, fn {binding, data} ->
            data.path == aggregate.relationship_path && data.type == :aggregate && binding
          end)
      end

    type = Ash.Type.ecto_type(attribute.type)

    filter_value_to_dynamic_expr(attribute, predicate, type, current_binding)
  end

  defp filter_value_to_dynamic_expr(attribute, %Eq{value: value}, _type, current_binding) do
    Ecto.Query.dynamic([{row, current_binding}], field(row, ^attribute.name) == ^value)
  end

  defp filter_value_to_dynamic_expr(attribute, %LessThan{value: value}, _type, current_binding) do
    Ecto.Query.dynamic([{row, current_binding}], field(row, ^attribute.name) < ^value)
  end

  defp filter_value_to_dynamic_expr(attribute, %GreaterThan{value: value}, _type, current_binding) do
    Ecto.Query.dynamic([{row, current_binding}], field(row, ^attribute.name) > ^value)
  end

  defp filter_value_to_dynamic_expr(attribute, %In{values: values}, _type, current_binding) do
    Ecto.Query.dynamic([{row, current_binding}], field(row, ^attribute.name) in ^values)
  end

  defp filter_value_to_dynamic_expr(attribute, %IsNil{nil?: true}, _type, current_binding) do
    Ecto.Query.dynamic([{row, current_binding}], is_nil(field(row, ^attribute.name)))
  end

  defp filter_value_to_dynamic_expr(attribute, %IsNil{nil?: false}, _type, current_binding) do
    Ecto.Query.dynamic([{row, current_binding}], not is_nil(field(row, ^attribute.name)))
  end

  defp filter_value_to_dynamic_expr(attribute, %Trigram{} = trigram, _type, current_binding) do
    case trigram do
      %{equals: nil, greater_than: greater_than, less_than: nil, text: text} ->
        Ecto.Query.dynamic(
          [{row, current_binding}],
          fragment("similarity(?, ?) > ?", field(row, ^attribute.name), ^text, ^greater_than)
        )

      %{equals: nil, greater_than: nil, less_than: less_than, text: text} ->
        Ecto.Query.dynamic(
          [{row, current_binding}],
          fragment("similarity(?, ?) < ?", field(row, ^attribute.name), ^text, ^less_than)
        )

      %{equals: nil, greater_than: greater_than, less_than: less_than, text: text} ->
        Ecto.Query.dynamic(
          [{row, current_binding}],
          fragment(
            "similarity(?, ?) BETWEEN ? AND ?",
            field(row, ^attribute.name),
            ^text,
            ^less_than,
            ^greater_than
          )
        )

      %{equals: equals, text: text} ->
        Ecto.Query.dynamic(
          [{row, current_binding}],
          fragment("similarity(?, ?) = ?", field(row, ^attribute.name), ^text, ^equals)
        )
    end
  end

  # IMPORTANT: We need to rework this so we don't need this hacky logic.
  # Specifically, we can't use dynamic expers in selects, so we need this for aggregates :(
  defp filter_to_expr(%Filter{expression: expression}, bindings, params) do
    filter_to_expr(expression, bindings, params)
  end

  # A nil filter means "everything"
  defp filter_to_expr(nil, _, _), do: {[], true}
  # A true filter means "everything"
  defp filter_to_expr(true, _, _), do: true
  # A false filter means "nothing"
  defp filter_to_expr(false, _, _), do: {[], false}

  defp filter_to_expr(%Expression{op: op, left: left, right: right}, bindings, params) do
    {params, left_expr} = filter_to_expr(left, bindings, params)
    {params, right_expr} = filter_to_expr(right, bindings, params)
    {params, {op, [], [left_expr, right_expr]}}
  end

  defp filter_to_expr(%Not{expression: expression}, bindings, params) do
    {params, new_expression} = filter_to_expr(expression, bindings, params)
    {params, {:not, [], [new_expression]}}
  end

  defp filter_to_expr(%Predicate{} = pred, bindings, params) do
    %{predicate: predicate, relationship_path: relationship_path, attribute: attribute} = pred

    current_binding =
      case attribute do
        %Ash.Resource.Attribute{} ->
          Enum.find_value(bindings, fn {binding, data} ->
            data.path == relationship_path && data.type in [:left, :root] && binding
          end)

        %Ash.Query.Aggregate{} = aggregate ->
          Enum.find_value(bindings, fn {binding, data} ->
            data.path == aggregate.relationship_path && data.type == :aggregate && binding
          end)
      end

    type = Ash.Type.ecto_type(attribute.type)

    filter_value_to_expr(attribute.name, predicate, type, current_binding, params)
  end

  defp filter_value_to_expr(attribute, %Eq{value: value}, type, current_binding, params) do
    simple_operator_expr(
      :==,
      params,
      value,
      type,
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(attribute, %LessThan{value: value}, type, current_binding, params) do
    simple_operator_expr(
      :<,
      params,
      value,
      type,
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(attribute, %GreaterThan{value: value}, type, current_binding, params) do
    simple_operator_expr(
      :>,
      params,
      value,
      type,
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(attribute, %In{values: values}, type, current_binding, params) do
    simple_operator_expr(
      :in,
      params,
      values,
      {:in, type},
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(attribute, %IsNil{nil?: true}, _type, current_binding, params) do
    {params, {:is_nil, [], [{{:., [], [{:&, [], [current_binding]}, attribute]}, [], []}]}}
  end

  defp filter_value_to_expr(attribute, %IsNil{nil?: false}, _type, current_binding, params) do
    {params,
     {:not, [], [{:is_nil, [], [{{:., [], [{:&, [], [current_binding]}, attribute]}, [], []}]}]}}
  end

  defp filter_value_to_expr(
         attribute,
         %Trigram{} = trigram,
         _type,
         current_binding,
         params
       ) do
    param_count = Enum.count(params)

    case trigram do
      %{equals: equals, greater_than: nil, less_than: nil, text: text} ->
        {params ++ [{text, {current_binding, attribute}}, {equals, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr: {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
            raw: ", ",
            expr: {:^, [], [param_count]},
            raw: ") = ",
            expr: {:^, [], [param_count + 1]},
            raw: ""
          ]}}

      %{equals: nil, greater_than: greater_than, less_than: nil, text: text} ->
        {params ++ [{text, {current_binding, attribute}}, {greater_than, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr: {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
            raw: ", ",
            expr: {:^, [], [param_count]},
            raw: ") > ",
            expr: {:^, [], [param_count + 1]},
            raw: ""
          ]}}

      %{equals: nil, greater_than: nil, less_than: less_than, text: text} ->
        {params ++ [{text, {current_binding, attribute}}, {less_than, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr: {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
            raw: ", ",
            expr: {:^, [], [param_count]},
            raw: ") < ",
            expr: {:^, [], [param_count + 1]},
            raw: ""
          ]}}

      %{equals: nil, greater_than: greater_than, less_than: less_than, text: text} ->
        {params ++
           [{text, {current_binding, attribute}}, {less_than, :float}, {greater_than, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr: {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
            raw: ", ",
            expr: {:^, [], [param_count]},
            raw: ") BETWEEN ",
            expr: {:^, [], [param_count + 1]},
            raw: " AND ",
            expr: {:^, [], [param_count + 2]},
            raw: ""
          ]}}
    end
  end

  defp simple_operator_expr(op, params, value, type, current_binding, attribute) do
    {params ++ [{value, type}],
     {op, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp add_binding(query, data) do
    current = query.__ash_bindings__.current
    bindings = query.__ash_bindings__.bindings

    new_ash_bindings = %{
      query.__ash_bindings__
      | bindings: Map.put(bindings, current, data),
        current: current + 1
    }

    %{query | __ash_bindings__: new_ash_bindings}
  end

  @impl true
  def transaction(resource, func) do
    repo(resource).transaction(func)
  end

  @impl true
  def rollback(resource, term) do
    repo(resource).rollback(term)
  end

  defp maybe_get_resource_query(resource) do
    {table(Delegate.get_delegated(resource)), resource}
  end
end
