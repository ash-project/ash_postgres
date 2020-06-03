defmodule AshPostgres do
  @using_opts_schema [
    repo: [
      type: :atom,
      required: true,
      doc:
        "The repo that will be used to fetch your data. See the `Ecto.Repo` documentation for more"
    ],
    table: [
      type: :string,
      doc: "The name of the database table backing the resource"
    ]
  ]

  alias Ash.Filter.{And, Eq, In, NotEq, NotIn, Or}
  alias AshPostgres.Predicates.Trigram

  @moduledoc """
  A postgres data layer that levereges Ecto's postgres tools.

  To use it, add `use AshPostgres, repo: MyRepo` to your resource, after `use Ash.Resource`

  #{NimbleOptions.docs(@using_opts_schema)}
  """
  @behaviour Ash.DataLayer

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      opts = AshPostgres.validate_using_opts(__MODULE__, opts)

      @data_layer AshPostgres
      @repo opts[:repo]
      @table opts[:table]

      def repo do
        @repo
      end

      def postgres_table do
        @table || @name
      end
    end
  end

  def validate_using_opts(mod, opts) do
    case NimbleOptions.validate(opts, @using_opts_schema) do
      {:ok, opts} ->
        opts

      {:error, [{key, message} | _]} ->
        raise Ash.Error.ResourceDslError,
          resource: mod,
          using: __MODULE__,
          option: key,
          message: message
    end
  end

  def postgres_repo?(repo) do
    repo.__adapter__() == Ecto.Adapters.Postgres
  end

  def repo(resource) do
    resource.repo()
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
  def can?(_, capability), do: can?(capability)
  def can?(:query_async), do: true
  def can?(:transact), do: true
  def can?(:composite_primary_key), do: true
  def can?(:upsert), do: true
  def can?({:filter, :in}), do: true
  def can?({:filter, :not_in}), do: true
  def can?({:filter, :not_eq}), do: true
  def can?({:filter, :eq}), do: true
  def can?({:filter, :and}), do: true
  def can?({:filter, :or}), do: true
  def can?({:filter, :not}), do: true
  def can?({:filter, :trigram}), do: true
  def can?({:filter_related, _}), do: true
  def can?(_), do: false

  @impl true
  def limit(query, nil, _), do: {:ok, query}

  def limit(query, limit, _resource) do
    {:ok, from(row in query, limit: ^limit)}
  end

  @impl true
  def offset(query, nil, _), do: query

  def offset(query, offset, _resource) do
    {:ok, from(row in query, offset: ^offset)}
  end

  @impl true
  def run_query(%{__impossible__: true}, _) do
    {:ok, []}
  end

  @impl true
  def run_query(query, resource) do
    {:ok, repo(resource).all(query)}
  end

  @impl true
  def resource_to_query(resource),
    do: Ecto.Queryable.to_query({resource.postgres_table(), resource})

  @impl true
  def create(resource, changeset) do
    changeset =
      Map.update!(changeset, :action, fn
        :create -> :insert
        action -> action
      end)

    changeset =
      Map.update!(changeset, :data, fn data ->
        Map.update!(data, :__meta__, &Map.put(&1, :source, resource.postgres_table()))
      end)

    repo(resource).insert(changeset)
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def upsert(resource, changeset) do
    changeset =
      Map.update!(changeset, :action, fn
        :create -> :insert
        action -> action
      end)

    changeset =
      Map.update!(changeset, :data, fn data ->
        Map.update!(data, :__meta__, &Map.put(&1, :source, resource.postgres_table()))
      end)

    repo(resource).insert(changeset,
      on_conflict: :replace_all,
      conflict_target: Ash.primary_key(resource)
    )
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def update(resource, changeset) do
    repo(resource).update(changeset)
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
  def filter(query, filter, _resource) do
    new_query =
      query
      |> Map.put(:bindings, %{})
      |> join_all_relationships(filter)
      |> add_filter_expression(filter)

    impossible_query =
      if filter.impossible? do
        Map.put(new_query, :__impossible__, true)
      else
        new_query
      end

    {:ok, impossible_query}
  end

  defp join_all_relationships(query, filter, path \\ []) do
    query =
      Map.put_new(query, :__ash_bindings__, %{current: Enum.count(query.joins) + 1, bindings: %{}})

    Enum.reduce(filter.relationships, query, fn {name, relationship_filter}, query ->
      join_type = :left

      case {join_type, relationship_filter} do
        {join_type, relationship_filter} ->
          relationship = Ash.relationship(filter.resource, name)

          current_path = [relationship | path]

          joined_query = join_relationship(query, current_path, join_type)

          joined_query_with_distinct =
            join_and_add_distinct(relationship, join_type, joined_query, filter)

          join_all_relationships(joined_query_with_distinct, relationship_filter, current_path)
      end
    end)
  end

  defp join_and_add_distinct(relationship, join_type, joined_query, filter) do
    if relationship.cardinality == :many and join_type == :left && !joined_query.distinct do
      from(row in joined_query,
        distinct: ^Ash.primary_key(filter.resource)
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

  defp join_exprs(nil, nil, _op), do: nil
  defp join_exprs(expr, nil, _op), do: expr
  defp join_exprs(nil, expr, _op), do: expr
  defp join_exprs(left_expr, right_expr, op), do: {op, [], [left_expr, right_expr]}

  defp filter_to_expr(filter, bindings, params, current_binding \\ 0, path \\ [])

  # A completely empty filter means "everything"
  defp filter_to_expr(%{impossible?: true}, _, _, _, _), do: {[], false}

  defp filter_to_expr(
         %{ands: [], ors: [], not: nil, attributes: attrs, relationships: rels},
         _,
         _,
         _,
         _
       )
       when attrs == %{} and rels == %{} do
    {[], true}
  end

  defp filter_to_expr(filter, bindings, params, current_binding, path) do
    {params, expr} =
      Enum.reduce(filter.attributes, {params, nil}, fn {attribute, filter},
                                                       {params, existing_expr} ->
        {params, new_expr} = filter_value_to_expr(attribute, filter, current_binding, params)

        {params, join_exprs(existing_expr, new_expr, :and)}
      end)

    {params, expr} =
      Enum.reduce(filter.relationships, {params, expr}, fn {relationship, relationship_filter},
                                                           {params, existing_expr} ->
        full_path = path ++ [relationship]

        binding =
          Map.get(bindings, full_path) ||
            raise "unbound relationship #{inspect(full_path)} referenced! #{inspect(bindings)}"

        {params, new_expr} =
          filter_to_expr(relationship_filter, bindings, params, binding.binding, full_path)

        {params, join_exprs(new_expr, existing_expr, :and)}
      end)

    {params, expr} =
      Enum.reduce(filter.ors, {params, expr}, fn or_filter, {params, existing_expr} ->
        {params, new_expr} = filter_to_expr(or_filter, bindings, params, current_binding, path)

        {params, join_exprs(existing_expr, new_expr, :or)}
      end)

    {params, expr} =
      case filter.not do
        nil ->
          {params, expr}

        not_filter ->
          {params, new_expr} = filter_to_expr(not_filter, bindings, params, current_binding, path)

          {params, join_exprs(expr, {:not, [], [new_expr]}, :and)}
      end

    {params, expr} =
      Enum.reduce(filter.ands, {params, expr}, fn and_filter, {params, existing_expr} ->
        {params, new_expr} = filter_to_expr(and_filter, bindings, params, current_binding, path)

        {params, join_exprs(existing_expr, new_expr, :and)}
      end)

    if expr do
      {params, expr}
    else
      # A filter that was not empty, but didn't generate an expr for some reason, should default to `false`
      # AFAIK this shouldn't actually be possible
      {params, false}
    end
  end

  # THe fact that we keep counting params here is very silly.
  defp filter_value_to_expr(attribute, %Eq{value: value}, current_binding, params) do
    {params ++ [{value, {current_binding, attribute}}],
     {:==, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp filter_value_to_expr(attribute, %NotEq{value: value}, current_binding, params) do
    {params ++ [{value, {current_binding, attribute}}],
     {:==, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp filter_value_to_expr(attribute, %In{values: values}, current_binding, params) do
    {params ++ [{values, {:in, {current_binding, attribute}}}],
     {:in, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp filter_value_to_expr(
         attribute,
         %NotIn{values: values},
         current_binding,
         params
       ) do
    {params ++ [{values, {:in, {current_binding, attribute}}}],
     {:not,
      {:in, [],
       [
         {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
         {:^, [], [Enum.count(params)]}
       ]}}}
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

  defp filter_value_to_expr(
         attribute,
         %And{left: left, right: right},
         current_binding,
         params
       ) do
    {params, left_expr} = filter_value_to_expr(attribute, left, current_binding, params)

    {params, right_expr} = filter_value_to_expr(attribute, right, current_binding, params)

    {params, join_exprs(left_expr, right_expr, :and)}
  end

  defp filter_value_to_expr(
         attribute,
         %Or{left: left, right: right},
         current_binding,
         params
       ) do
    {params, left_expr} = filter_value_to_expr(attribute, left, current_binding, params)

    {params, right_expr} = filter_value_to_expr(attribute, right, current_binding, params)

    {params, join_exprs(left_expr, right_expr, :or)}
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
  def can_query_async?(resource) do
    repo(resource).in_transaction?()
  end

  @impl true
  def transaction(resource, func) do
    repo(resource).transaction(func)
  end

  defp maybe_get_resource_query(resource) do
    if Ash.resource_module?(resource) do
      {resource.postgres_table(), resource}
    else
      resource
    end
  end
end
