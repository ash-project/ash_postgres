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

  alias Ash.Filter
  alias Ash.Filter.{Expression, Not, Predicate}
  alias Ash.Filter.Predicate.{Eq, GreaterThan, In, LessThan}
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
    if "pg_trgm" in config[:installed_extensions] do
      Map.update(filters, :string, [{:trigram, AshPostgres.Predicates.Trigram}], fn filters ->
        [{:trigram, AshPostgres.Predicates.Trigram} | filters]
      end)
    else
      filters
    end
  end

  import Ecto.Query, only: [from: 2]

  @impl true
  def can?(_, :async_engine), do: true
  def can?(_, :transact), do: true
  def can?(_, :composite_primary_key), do: true
  def can?(_, :upsert), do: true
  def can?(_, :join), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, {:filter_predicate, _, %In{}}), do: true
  def can?(_, {:filter_predicate, _, %Eq{}}), do: true
  def can?(_, {:filter_predicate, _, %LessThan{}}), do: true
  def can?(_, {:filter_predicate, _, %GreaterThan{}}), do: true
  def can?(_, {:filter_predicate, :string, %Trigram{}}), do: true
  def can?(_, {:filter_predicate, _}), do: false

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
      conflict_target: Ash.primary_key(resource)
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
  def destroy(%resource{} = record) do
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
    {:ok,
     from(row in query,
       order_by: ^sanitize_sort(sort)
     )}
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

  defp relationship_path_to_relationships(resource, path, acc \\ [])
  defp relationship_path_to_relationships(_resource, [], acc), do: Enum.reverse(acc)

  defp relationship_path_to_relationships(resource, [relationship | rest], acc) do
    relationship = Ash.relationship(resource, relationship)

    relationship_path_to_relationships(relationship.destination, rest, [relationship | acc])
  end

  defp join_all_relationships(query, _resource, relationship_paths, path \\ []) do
    query =
      Map.put_new(query, :__ash_bindings__, %{
        current: Enum.count(query.joins) + 1,
        bindings: %{[] => %{binding: 0, type: :root}}
      })

    Enum.reduce(relationship_paths, query, fn [relationship | rest_rels], query ->
      # Eventually this will not be a constant
      join_type = :left

      current_path = [relationship | path]

      joined_query = join_relationship(query, current_path, join_type)

      joined_query_with_distinct = join_and_add_distinct(relationship, join_type, joined_query)

      join_all_relationships(
        joined_query_with_distinct,
        relationship.destination,
        rest_rels,
        current_path
      )
    end)
  end

  defp join_and_add_distinct(relationship, join_type, joined_query) do
    if relationship.cardinality == :many and join_type == :left && !joined_query.distinct do
      from(row in joined_query,
        distinct: ^Ash.primary_key(relationship.destination)
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
  defp do_join_relationship(_, [], _, _), do: nil

  defp do_join_relationship(query, [%{type: :many_to_many} = relationship | rest], :inner, path) do
    relationship_through = maybe_get_resource_query(relationship.through)

    relationship_destination =
      do_join_relationship(query, rest, :inner, [relationship.name | path]) ||
        Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    new_query =
      from(row in query,
        join: through in ^relationship_through,
        on:
          field(row, ^relationship.source_field) ==
            field(through, ^relationship.source_field_on_join_table),
        join: destination in ^relationship_destination,
        on:
          field(destination, ^relationship.destination_field) ==
            field(through, ^relationship.destination_field_on_join_table)
      )

    join_path =
      Enum.reverse([String.to_existing_atom(to_string(relationship.name) <> "_join_assoc") | path])

    full_path = Enum.reverse([relationship.name | path])

    new_query
    |> add_binding(join_path, :inner)
    |> add_binding(full_path, :inner)
    |> merge_bindings(relationship_destination)
  end

  defp do_join_relationship(query, [relationship | rest], :inner, path) do
    relationship_destination =
      do_join_relationship(query, rest, :inner, [relationship.name | path]) ||
        Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    new_query =
      from(row in query,
        join: destination in ^relationship_destination,
        on:
          field(row, ^relationship.source_field) ==
            field(destination, ^relationship.destination_field)
      )

    new_query
    |> add_binding(Enum.reverse([relationship.name | path]), :inner)
    |> merge_bindings(relationship_destination)
  end

  defp do_join_relationship(query, [%{type: :many_to_many} = relationship | rest], :left, path) do
    relationship_through = maybe_get_resource_query(relationship.through)

    relationship_destination =
      do_join_relationship(query, rest, :inner, [relationship.name | path]) ||
        Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    new_query =
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

    join_path =
      Enum.reverse([String.to_existing_atom(to_string(relationship.name) <> "_join_assoc") | path])

    full_path = Enum.reverse([relationship.name | path])

    new_query
    |> add_binding(join_path, :left)
    |> add_binding(full_path, :left)
    |> merge_bindings(relationship_destination)
  end

  defp do_join_relationship(query, [relationship | rest], :left, path) do
    relationship_destination =
      do_join_relationship(query, rest, :inner, [relationship.name | path]) ||
        Ecto.Queryable.to_query(maybe_get_resource_query(relationship.destination))

    new_query =
      from(row in query,
        left_join: destination in ^relationship_destination,
        on:
          field(row, ^relationship.source_field) ==
            field(destination, ^relationship.destination_field)
      )

    new_query
    |> add_binding(Enum.reverse([relationship.name | path]), :left)
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

    current_binding = Map.get(bindings, relationship_path).binding

    filter_value_to_expr(attribute.name, predicate, current_binding, params)
  end

  defp filter_value_to_expr(attribute, %Eq{value: value}, current_binding, params) do
    simple_operator_expr(
      :==,
      params,
      value,
      {current_binding, attribute},
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(attribute, %LessThan{value: value}, current_binding, params) do
    simple_operator_expr(
      :<,
      params,
      value,
      {current_binding, attribute},
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(attribute, %GreaterThan{value: value}, current_binding, params) do
    simple_operator_expr(
      :>,
      params,
      value,
      {current_binding, attribute},
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(attribute, %In{values: values}, current_binding, params) do
    simple_operator_expr(
      :in,
      params,
      values,
      {:in, {current_binding, attribute}},
      current_binding,
      attribute
    )
  end

  defp filter_value_to_expr(
         attribute,
         %Trigram{} = trigram,
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
    |> Enum.reduce(query, fn {path, data}, query ->
      add_binding(query, path, data)
    end)
  end

  defp merge_bindings(query, _) do
    query
  end

  defp add_binding(query, path, type) do
    current = query.__ash_bindings__.current
    bindings = query.__ash_bindings__.bindings

    new_ash_bindings = %{
      query.__ash_bindings__
      | bindings: do_add_binding(bindings, path, current, type),
        current: current + 1
    }

    %{query | __ash_bindings__: new_ash_bindings}
  end

  defp do_add_binding(bindings, path, current, type) do
    Map.put(bindings, path, %{binding: current, type: type})
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
    {table(resource), resource}
  end
end
