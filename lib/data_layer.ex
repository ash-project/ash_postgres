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
  def sort(query, sort, _resource) do
    query = default_bindings(query)

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

  def filter(query, filter, resource) do
    relationship_paths =
      filter
      |> Filter.relationship_paths()
      |> Enum.map(fn path ->
        relationship_path_to_relationships(resource, path)
      end)

    new_query =
      query
      |> join_all_relationships(resource, relationship_paths)
      |> add_filter_expression(filter)

    {:ok, new_query}
  end

  defp default_bindings(query) do
    Map.put_new(query, :__ash_bindings__, %{
      current: Enum.count(query.joins) + 1,
      aggregates: %{},
      bindings: %{0 => %{path: [], type: :root}}
    })
  end

  @impl true
  def add_aggregate(query, aggregate, resource) do
    query = default_bindings(query)

    {query, binding} =
      case get_binding(resource, aggregate.relationship_path, query, :aggregate) do
        nil ->
          relationship = Ash.Resource.relationship(resource, aggregate.relationship_path)
          subquery = aggregate_subquery(relationship, aggregate)

          new_query =
            join_relationship(
              query,
              relationship_path_to_relationships(resource, aggregate.relationship_path),
              {:aggregate, aggregate.name, subquery}
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
    query = default_bindings(query)
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

  defp join_all_relationships(query, resource, relationship_paths, path \\ []) do
    query = default_bindings(query)

    Enum.reduce(relationship_paths, query, fn [relationship | rest_rels], query ->
      # Eventually this will not be a constant
      join_type = :left

      current_path = [relationship | path]

      if has_binding?(resource, Enum.reverse(current_path), query, :aggregate) do
        query
      else
        joined_query = join_relationship(query, current_path, join_type)

        joined_query_with_distinct = add_distinct(relationship, join_type, joined_query)

        join_all_relationships(
          joined_query_with_distinct,
          relationship.destination,
          rest_rels,
          current_path
        )
      end
    end)
  end

  defp has_binding?(resource, path, %{__ash_bindings__: _} = query, type) do
    paths =
      Enum.flat_map(query.__ash_bindings__.bindings, fn
        {_, %{path: path, type: ^type}} ->
          [path]

        _ ->
          []
      end)

    Enum.any?(paths, &Ash.SatSolver.synonymous_relationship_paths?(resource, &1, path))
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

  defp join_relationship(query, path, join_type) do
    path_names = Enum.map(path, & &1.name)

    case Map.get(query.__ash_bindings__.bindings, path_names) do
      %{type: existing_join_type} when join_type != existing_join_type ->
        raise "unreachable?"

      nil ->
        do_join_relationship(query, path, join_type)

      _ ->
        query
    end
  end

  defp do_join_relationship(query, relationships, kind, path \\ [])

  defp do_join_relationship(_query, [], {:aggregate, _, subquery}, _path) do
    {:left_lateral, subquery}
  end

  defp do_join_relationship(_, [], _, _), do: nil

  defp do_join_relationship(query, [%{type: :many_to_many} = relationship | rest], kind, path) do
    relationship_through = maybe_get_resource_query(relationship.through)

    relationship_destination =
      do_join_relationship(query, rest, kind, [relationship.name | path]) ||
        Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    new_query =
      case relationship_destination do
        {:left_lateral, subquery} ->
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

          from(row in query,
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

        relationship_destination ->
          from(row in query,
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
      case {kind, rest} do
        {{:aggregate, name, _agg}, []} -> %{type: :aggregate, name: name, path: full_path}
        _ -> %{type: :left, path: full_path}
      end

    new_query
    |> add_binding(%{path: join_path, type: :left})
    |> add_binding(binding_data)
    |> merge_bindings(relationship_destination)
  end

  defp do_join_relationship(query, [relationship | rest], kind, path) do
    relationship_destination =
      do_join_relationship(query, rest, kind, [relationship.name | path]) ||
        Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    new_query =
      case relationship_destination do
        {:left_lateral, subquery} ->
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

          from(row in query,
            as: :rel_source,
            left_lateral_join: destination in ^subquery,
            on:
              field(row, ^relationship.source_field) ==
                field(destination, ^relationship.destination_field)
          )

        relationship_destination ->
          from(row in query,
            left_join: destination in ^relationship_destination,
            on:
              field(row, ^relationship.source_field) ==
                field(destination, ^relationship.destination_field)
          )
      end

    full_path = Enum.reverse([relationship.name | path])

    binding_data =
      case {kind, rest} do
        {{:aggregate, name, _agg}, []} -> %{type: :aggregate, name: name, path: full_path}
        _ -> %{type: :left, path: full_path}
      end

    new_query
    |> add_binding(binding_data)
    |> merge_bindings(relationship_destination)
  end

  defp add_filter_expression(query, filter) do
    {params, expr} = filter_to_expr(filter, query.__ash_bindings__.bindings, [])

    if expr do
      boolean_expr = %Ecto.Query.BooleanExpr{
        expr: expr,
        op: :and,
        params: params
      }

      %{query | wheres: [boolean_expr | query.wheres]}
    else
      query
    end
  end

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

  defp merge_bindings(query, %{__ash_bindings__: ash_bindings}) do
    ash_bindings
    |> Map.get(:bindings)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(query, fn {_binding, data}, query ->
      add_binding(query, data)
    end)
  end

  defp merge_bindings(query, _) do
    query
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
