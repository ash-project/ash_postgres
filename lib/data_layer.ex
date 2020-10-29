defmodule AshPostgres.DataLayer do
  @moduledoc """
  A postgres data layer that levereges Ecto's postgres capabilities.

  AshPostgres supports all capabilities of an Ash data layer, and it will
  most likely stay that way, as postgres is the primary target/most maintained
  data layer.

  Custom Predicates:

  * AshPostgres.Predicates.Trigram

  ### Usage

  First, ensure you've added ash_postgres to your `mix.exs` file.

  ```elixir
  {:ash_postgres, "~> x.y.z"}
  ```

  To use this data layer, you need to define an `Ecto.Repo`. AshPostgres adds some
  functionality on top of ecto repos, so you'll want to use `AshPostgres.Repo`

  Then, configure your resource like so:

  ```elixir
  postgres do
    repo MyApp.Repo
    table "table_name"
  end
  ```

  ### Generating Migrations

  See the documentation for `Mix.Tasks.AshPostgres.GenerateMigrations` for how to generate
  migrations from your resources
  """

  @manage_tenant %Ash.Dsl.Section{
    name: :manage_tenant,
    describe: """
    Configuration for the behavior of a resource that manages a tenant
    """,
    schema: [
      template: [
        type: {:custom, __MODULE__, :tenant_template, []},
        required: true,
        doc: """
        A template that will cause the resource to create/manage the specified schema.

        Use this if you have a resource that, when created, it should create a new tenant
        for you. For example, if you have a `customer` resource, and you want to create
        a schema for each customer based on their id, e.g `customer_10` set this option
        to `["customer_", :id]`. Then, when this is created, it will create a schema called
        `["customer_", :id]`, and run your tenant migrations on it. Then, if you were to change
        that customer's id to `20`, it would rename the schema to `customer_20`. Generally speaking
        you should avoid changing the tenant id.
        """
      ],
      create?: [
        type: :boolean,
        default: true,
        doc: "Whether or not to automatically create a tenant when a record is created"
      ],
      update?: [
        type: :boolean,
        default: true,
        doc: "Whether or not to automatically update the tenant name if the record is udpated"
      ]
    ]
  }

  @postgres %Ash.Dsl.Section{
    name: :postgres,
    describe: """
    Postgres data layer configuration
    """,
    sections: [
      @manage_tenant
    ],
    schema: [
      repo: [
        type: :atom,
        required: true,
        doc:
          "The repo that will be used to fetch your data. See the `AshPostgres.Repo` documentation for more"
      ],
      migrate?: [
        type: :boolean,
        default: true,
        doc:
          "Whether or not to include this resource in the generated migrations with `mix ash.generate_migrations`"
      ],
      base_filter_sql: [
        type: :string,
        doc:
          "A raw sql version of the base_filter, e.g `representative = true`. Required if trying to create a unique constraint on a resource with a base_filter"
      ],
      skip_unique_indexes: [
        type: {:custom, __MODULE__, :validate_skip_unique_indexes, []},
        default: false,
        doc: "Skip generating unique indexes when generating migrations"
      ],
      table: [
        type: :string,
        required: true,
        doc: "The table to store and read the resource from"
      ]
    ]
  }

  alias Ash.Filter
  alias Ash.Query.{Expression, Not, Ref}

  alias Ash.Query.Operator.{
    Eq,
    GreaterThan,
    GreaterThanOrEqual,
    In,
    IsNil,
    LessThan,
    LessThanOrEqual
  }

  alias AshPostgres.Functions.TrigramSimilarity

  import AshPostgres, only: [table: 1, repo: 1]

  @behaviour Ash.DataLayer

  use Ash.Dsl.Extension,
    sections: [@postgres],
    transformers: [AshPostgres.Transformers.VerifyRepo]

  @doc false
  def tenant_template(value) do
    value = List.wrap(value)

    if Enum.all?(value, &(is_binary(&1) || is_atom(&1))) do
      {:ok, value}
    else
      {:error, "Expected all values for `manages_tenant` to be strings or atoms"}
    end
  end

  @doc false
  def validate_skip_unique_indexes(indexes) do
    indexes = List.wrap(indexes)

    if Enum.all?(indexes, &is_atom/1) do
      {:ok, indexes}
    else
      {:error, "All indexes to skip must be atoms"}
    end
  end

  import Ecto.Query, only: [from: 2, subquery: 1]

  @impl true
  def can?(_, :async_engine), do: true
  def can?(_, :transact), do: true
  def can?(_, :composite_primary_key), do: true
  def can?(_, :upsert), do: true

  def can?(resource, {:join, other_resource}) do
    data_layer = Ash.Resource.data_layer(resource)
    other_data_layer = Ash.Resource.data_layer(other_resource)
    data_layer == other_data_layer and repo(data_layer) == repo(other_data_layer)
  end

  def can?(resource, {:lateral_join, other_resource}) do
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
  def can?(_, :multitenancy), do: true
  def can?(_, {:filter_operator, %{right: %Ref{}}}), do: false
  def can?(_, {:filter_operator, %Eq{left: %Ref{}}}), do: true
  def can?(_, {:filter_operator, %In{left: %Ref{}}}), do: true
  def can?(_, {:filter_operator, %LessThan{left: %Ref{}}}), do: true
  def can?(_, {:filter_operator, %GreaterThan{left: %Ref{}}}), do: true
  def can?(_, {:filter_operator, %LessThanOrEqual{left: %Ref{}}}), do: true
  def can?(_, {:filter_operator, %GreaterThanOrEqual{left: %Ref{}}}), do: true
  def can?(_, {:filter_operator, %IsNil{left: %Ref{}}}), do: true
  def can?(_, {:filter_function, %TrigramSimilarity{}}), do: true
  def can?(_, {:query_aggregate, :count}), do: true
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

  def offset(%{offset: old_offset} = query, 0, _resource) when old_offset in [0, nil] do
    {:ok, query}
  end

  def offset(query, offset, _resource) do
    {:ok, from(row in query, offset: ^offset)}
  end

  @impl true
  def run_query(query, resource) do
    {:ok, repo(resource).all(query, repo_opts(query))}
  end

  defp repo_opts(%Ash.Changeset{tenant: tenant, resource: resource}) do
    repo_opts(%{tenant: tenant, resource: resource})
  end

  defp repo_opts(%{tenant: tenant, resource: resource}) when not is_nil(tenant) do
    if Ash.Resource.multitenancy_strategy(resource) == :context do
      [prefix: tenant]
    else
      []
    end
  end

  defp repo_opts(_), do: []

  @impl true
  def functions(resource) do
    config = repo(resource).config()

    if "pg_trgm" in (config[:installed_extensions] || []) do
      [
        AshPostgres.Functions.TrigramSimilarity
      ]
    else
      []
    end
  end

  @impl true
  def run_aggregate_query(query, aggregates, resource) do
    subquery = from(row in subquery(query), select: %{})

    query =
      Enum.reduce(
        aggregates,
        subquery,
        &add_subquery_aggregate_select(&2, &1, resource)
      )

    {:ok, repo(resource).one(query, repo_opts(query))}
  end

  @impl true
  def set_tenant(_resource, query, tenant) do
    {:ok, Ecto.Query.put_query_prefix(query, to_string(tenant))}
  end

  @impl true
  def run_aggregate_query_with_lateral_join(
        query,
        aggregates,
        root_data,
        source_resource,
        destination_resource,
        source_field,
        destination_field
      ) do
    lateral_join_query =
      lateral_join_query(
        query,
        root_data,
        source_resource,
        source_field,
        destination_field
      )

    subquery = from(row in subquery(lateral_join_query), select: %{})

    query =
      Enum.reduce(
        aggregates,
        subquery,
        &add_subquery_aggregate_select(&2, &1, destination_resource)
      )

    {:ok, repo(source_resource).one(query, repo_opts(:query))}
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
    query =
      lateral_join_query(
        query,
        root_data,
        source_resource,
        source_field,
        destination_field
      )

    {:ok, repo(source_resource).all(query, repo_opts(query))}
  end

  defp lateral_join_query(
         query,
         root_data,
         source_resource,
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

    data_layer_query = Ash.Query.new(source_resource).data_layer_query

    from(source in data_layer_query,
      as: :source_record,
      where: field(source, ^source_field) in ^source_values,
      inner_lateral_join: destination in ^subquery,
      on: field(source, ^source_field) == field(destination, ^destination_field),
      select: destination
    )
  end

  @impl true
  def resource_to_query(resource),
    do: Ecto.Queryable.to_query({table(resource), resource})

  @impl true
  def create(resource, changeset) do
    changeset.data
    |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource)))
    |> ecto_changeset(changeset)
    |> repo(resource).insert(repo_opts(changeset))
    |> case do
      {:ok, result} ->
        case maybe_create_tenant(resource, result) do
          :ok ->
            {:ok, result}

          {:error, error} ->
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  rescue
    e ->
      {:error, e}
  end

  defp maybe_create_tenant(resource, result) do
    if AshPostgres.manage_tenant_create?(resource) do
      tenant_name = tenant_name(resource, result)

      AshPostgres.MultiTenancy.create_tenant(tenant_name, repo(resource))
    else
      :ok
    end
  end

  defp maybe_update_tenant(resource, changeset, result) do
    if AshPostgres.manage_tenant_update?(resource) do
      changing_tenant_name? =
        resource
        |> AshPostgres.manage_tenant_template()
        |> Enum.filter(&is_atom/1)
        |> Enum.any?(&Ash.Changeset.changing_attribute?(changeset, &1))

      if changing_tenant_name? do
        old_tenant_name = tenant_name(resource, changeset.data)

        new_tenant_name = tenant_name(resource, result)
        AshPostgres.MultiTenancy.rename_tenant(repo(resource), old_tenant_name, new_tenant_name)
      end
    end

    :ok
  end

  defp tenant_name(resource, result) do
    resource
    |> AshPostgres.manage_tenant_template()
    |> Enum.map_join(fn item ->
      if is_binary(item) do
        item
      else
        result
        |> Map.get(item)
        |> to_string()
      end
    end)
  end

  defp ecto_changeset(record, changeset) do
    Ecto.Changeset.change(record, changeset.attributes)
  end

  @impl true
  def upsert(resource, changeset) do
    repo_opts =
      changeset
      |> repo_opts()
      |> Keyword.put(:on_conflict, {:replace, Map.keys(changeset.attributes)})
      |> Keyword.put(:conflict_target, Ash.Resource.primary_key(resource))

    if AshPostgres.manage_tenant_update?(resource) do
      {:error, "Cannot currently upsert a resource that owns a tenant"}
    else
      changeset.data
      |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource)))
      |> ecto_changeset(changeset)
      |> repo(resource).insert(repo_opts)
    end
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def update(resource, changeset) do
    changeset.data
    |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource)))
    |> ecto_changeset(changeset)
    |> repo(resource).update(repo_opts(changeset))
    |> case do
      {:ok, result} ->
        maybe_update_tenant(resource, changeset, result)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def destroy(resource, %{data: record} = changeset) do
    case repo(resource).delete(record, repo_opts(changeset)) do
      {:ok, _record} ->
        :ok

      {:error, error} ->
        {:error, error}
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
    |> Enum.reduce({:ok, query}, fn {order, sort}, {:ok, query} ->
      binding =
        case Map.fetch(query.__ash_bindings__.aggregates, sort) do
          {:ok, binding} ->
            binding

          :error ->
            0
        end

      new_query =
        Map.update!(query, :order_bys, fn order_bys ->
          order_bys = order_bys || []

          sort_expr = %Ecto.Query.QueryExpr{
            expr: [
              {order, {{:., [], [{:&, [], [binding]}, sort]}, [], []}}
            ]
          }

          order_bys ++ [sort_expr]
        end)

      {:ok, new_query}
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

  defp can_inner_join?(
         search_path,
         %{__operator__?: true, left: %Ref{relationship_path: relationship_path}},
         seen_an_or?
       )
       when search_path == relationship_path do
    not seen_an_or?
  end

  defp can_inner_join?(
         search_path,
         %{__function__?: true, arguments: arguments},
         seen_an_or?
       ) do
    if Enum.any?(arguments, &match?(%Ref{relationship_path: ^search_path}, &1)) do
      not seen_an_or?
    else
      true
    end
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

  defp aggregate_subquery(relationship, aggregate) do
    query =
      from(row in relationship.destination,
        group_by: ^relationship.destination_field,
        select: field(row, ^relationship.destination_field)
      )

    if aggregate.query && aggregate.query.tenant do
      Ecto.Query.put_query_prefix(query, aggregate.query.tenant)
    else
      query
    end
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
    wheres =
      filter
      |> split_and_statements()
      |> Enum.map(fn filter ->
        {params, expr} = filter_to_expr(filter, query.__ash_bindings__.bindings, [])

        %Ecto.Query.BooleanExpr{
          expr: expr,
          op: :and,
          params: params
        }
      end)

    %{query | wheres: query.wheres ++ wheres}
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

  defp split_and_statements(%Not{
         expression: %Expression{op: :or, left: left, right: right}
       }) do
    split_and_statements(%Expression{
      op: :and,
      left: %Not{expression: left},
      right: %Not{expression: right}
    })
  end

  defp split_and_statements(other), do: [other]

  defp filter_to_expr(%Filter{expression: expression}, bindings, params) do
    filter_to_expr(expression, bindings, params)
  end

  # A nil filter means "everything"
  defp filter_to_expr(nil, _, _), do: {[], true}
  # A true filter means "everything"
  defp filter_to_expr(true, _, _), do: {[], true}
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

  defp filter_to_expr(
         %In{left: %Ref{} = left, right: map_set, embedded?: embedded?},
         bindings,
         params
       ) do
    simple_operator_expr(
      :in,
      params,
      MapSet.to_list(map_set),
      {:in, left.attribute.type},
      ref_binding(left, bindings),
      left.attribute,
      embedded?
    )
  end

  defp filter_to_expr(
         %IsNil{left: %Ref{} = left, right: nil?},
         bindings,
         params
       ) do
    if nil? do
      {params,
       {:is_nil, [],
        [{{:., [], [{:&, [], [ref_binding(left, bindings)]}, left.attribute.name]}, [], []}]}}
    else
      {params,
       {:not, [],
        [
          {:is_nil, [],
           [{{:., [], [{:&, [], [ref_binding(left, bindings)]}, left.attribute.name]}, [], []}]}
        ]}}
    end
  end

  defp filter_to_expr(
         %{operator: operator, left: %Ref{} = left, right: right, embedded?: embedded?},
         bindings,
         params
       ) do
    simple_operator_expr(
      operator,
      params,
      right,
      left.attribute.type,
      ref_binding(left, bindings),
      left.attribute,
      embedded?
    )
  end

  defp filter_to_expr(
         %TrigramSimilarity{arguments: [%Ref{} = ref, text, options], embedded?: false},
         bindings,
         params
       ) do
    param_count = Enum.count(params)

    case Enum.into(options, %{}) do
      %{equals: equals, greater_than: nil, less_than: nil} ->
        {params ++ [{text, :string}, {equals, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
            raw: ", ",
            expr: {:^, [], [param_count]},
            raw: ") = ",
            expr: {:^, [], [param_count + 1]},
            raw: ""
          ]}}

      %{equals: nil, greater_than: greater_than, less_than: nil} ->
        {params ++ [{text, :string}, {greater_than, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
            raw: ", ",
            expr: {:^, [], [param_count]},
            raw: ") > ",
            expr: {:^, [], [param_count + 1]},
            raw: ""
          ]}}

      %{equals: nil, greater_than: nil, less_than: less_than} ->
        {params ++ [{text, :string}, {less_than, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
            raw: ", ",
            expr: {:^, [], [param_count]},
            raw: ") < ",
            expr: {:^, [], [param_count + 1]},
            raw: ""
          ]}}

      %{equals: nil, greater_than: greater_than, less_than: less_than} ->
        {params ++
           [{text, :string}, {less_than, :float}, {greater_than, :float}],
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
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

  defp filter_to_expr(
         %TrigramSimilarity{arguments: [%Ref{} = ref, text, options], embedded?: true},
         bindings,
         params
       ) do
    case Enum.into(options, %{}) do
      %{equals: equals, greater_than: nil, less_than: nil} ->
        {params,
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
            raw: ", ",
            expr: tagged(text, :string),
            raw: ") = ",
            expr: tagged(equals, :float),
            raw: ""
          ]}}

      %{equals: nil, greater_than: greater_than, less_than: nil} ->
        {params,
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
            raw: ", ",
            expr: tagged(text, :string),
            raw: ") > ",
            expr: tagged(greater_than, :float),
            raw: ""
          ]}}

      %{equals: nil, greater_than: nil, less_than: less_than} ->
        {params,
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
            raw: ", ",
            expr: tagged(text, :string),
            raw: ") < ",
            expr: tagged(less_than, :float),
            raw: ""
          ]}}

      %{equals: nil, greater_than: greater_than, less_than: less_than} ->
        {params,
         {:fragment, [],
          [
            raw: "similarity(",
            expr:
              {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, ref.attribute.name]}, [], []},
            raw: ", ",
            expr: tagged(text, :string),
            raw: ") BETWEEN ",
            expr: tagged(less_than, :float),
            raw: " AND ",
            expr: tagged(greater_than, :float),
            raw: ""
          ]}}
    end
  end

  defp ref_binding(ref, bindings) do
    case ref.attribute do
      %Ash.Resource.Attribute{} ->
        Enum.find_value(bindings, fn {binding, data} ->
          data.path == ref.relationship_path && data.type in [:inner, :left, :root] && binding
        end)

      %Ash.Query.Aggregate{} = aggregate ->
        Enum.find_value(bindings, fn {binding, data} ->
          data.path == aggregate.relationship_path && data.type == :aggregate && binding
        end)
    end
  end

  defp simple_operator_expr(op, params, value, type, current_binding, attribute, false) do
    {params ++ [{value, op_type(type)}],
     {op, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute.name]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp simple_operator_expr(op, params, value, type, current_binding, attribute, true) do
    {params,
     {op, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute.name]}, [], []},
        tagged(value, type)
      ]}}
  end

  defp op_type({:in, type}) do
    {:in, op_type(type)}
  end

  defp op_type(type) do
    Ash.Type.ecto_type(type)
  end

  defp tagged(value, type) do
    %Ecto.Query.Tagged{value: value, type: get_type(type)}
  end

  defp get_type({:array, type}) do
    {:array, get_type(type)}
  end

  defp get_type(type) do
    if Ash.Type.ash_type?(type) do
      Ash.Type.storage_type(type)
    else
      type
    end
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
    case Ash.Query.data_layer_query(Ash.Query.new(resource), only_validate_filter?: false) do
      {:ok, query} -> query
      {:error, error} -> {:error, error}
    end
  end
end
