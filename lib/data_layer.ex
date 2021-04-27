defmodule AshPostgres.DataLayer do
  @manage_tenant %Ash.Dsl.Section{
    name: :manage_tenant,
    describe: """
    Configuration for the behavior of a resource that manages a tenant
    """,
    examples: [
      """
      manage_tenant do
        template ["organization_", :id]
        create? true
        update? false
      end
      """
    ],
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

  @reference %Ash.Dsl.Entity{
    name: :reference,
    describe: """
    Configures the reference for a relationship in resource migrations.

    Keep in mind that multiple relationships can theoretically involve the same destination and foreign keys.
    In those cases, you only need to configure the `reference` behavior for one of them. Any conflicts will result
    in an error, across this resource and any other resources that share a table with this one. For this reason,
    instead of adding a reference configuration for `:nothing`, its best to just leave the configuration out, as that
    is the default behavior if *no* relationship anywhere has configured the behavior of that reference.
    """,
    examples: [
      "reference :post, on_delete: :delete, on_update: :update, name: \"comments_to_posts_fkey\""
    ],
    args: [:relationship],
    target: AshPostgres.Reference,
    schema: AshPostgres.Reference.schema()
  }

  @references %Ash.Dsl.Section{
    name: :references,
    describe: """
    A section for configuring the references (foreign keys) in resource migrations.

    This section is only relevant if you are using the migration generator with this resource.
    Otherwise, it has no effect.
    """,
    examples: [
      """
      references do
        reference :post, on_delete: :delete, on_update: :update, name: "comments_to_posts_fkey"
      end
      """
    ],
    entities: [@reference],
    schema: [
      polymorphic_on_delete: [
        type: {:one_of, [:delete, :nilify, :nothing, :restrict]},
        doc:
          "For polymorphic resources, configures the on_delete behavior of the automatically generated foreign keys to source tables."
      ],
      polymorphic_on_update: [
        type: {:one_of, [:update, :nilify, :nothing, :restrict]},
        doc:
          "For polymorphic resources, configures the on_update behavior of the automatically generated foreign keys to source tables."
      ],
      polymorphic_name: [
        type: {:one_of, [:update, :nilify, :nothing, :restrict]},
        doc:
          "For polymorphic resources, configures the on_update behavior of the automatically generated foreign keys to source tables."
      ]
    ]
  }

  @check_constraint %Ash.Dsl.Entity{
    name: :check_constraint,
    describe: """
    Add a check constraint to be validated.

    If a check constraint exists on the table but not in this section, and it produces an error, a runtime error will be raised.

    Provide a list of attributes instead of a single attribute to add the message to multiple attributes.

    By adding the `check` option, the migration generator will include it when generating migrations.
    """,
    examples: [
      """
      check_constraint :price, "price_must_be_positive", check: "price > 0", message: "price must be positive"
      """
    ],
    args: [:attribute, :name],
    target: AshPostgres.CheckConstraint,
    schema: AshPostgres.CheckConstraint.schema()
  }

  @check_constraints %Ash.Dsl.Section{
    name: :check_constraints,
    describe: """
    A section for configuring the check constraints for a given table.

    This can be used to automatically create those check constraints, or just to provide message when they are raised
    """,
    examples: [
      """
      check_constraints do
        check_constraint :price, "price_must_be_positive", check: "price > 0", message: "price must be positive"
      end
      """
    ],
    entities: [@check_constraint]
  }

  @references %Ash.Dsl.Section{
    name: :references,
    describe: """
    A section for configuring the references (foreign keys) in resource migrations.

    This section is only relevant if you are using the migration generator with this resource.
    Otherwise, it has no effect.
    """,
    examples: [
      """
      references do
        reference :post, on_delete: :delete, on_update: :update, name: "comments_to_posts_fkey"
      end
      """
    ],
    entities: [@reference],
    schema: [
      polymorphic_on_delete: [
        type: {:one_of, [:delete, :nilify, :nothing, :restrict]},
        doc:
          "For polymorphic resources, configures the on_delete behavior of the automatically generated foreign keys to source tables."
      ],
      polymorphic_on_update: [
        type: {:one_of, [:update, :nilify, :nothing, :restrict]},
        doc:
          "For polymorphic resources, configures the on_update behavior of the automatically generated foreign keys to source tables."
      ],
      polymorphic_name: [
        type: {:one_of, [:update, :nilify, :nothing, :restrict]},
        doc:
          "For polymorphic resources, configures the on_update behavior of the automatically generated foreign keys to source tables."
      ]
    ]
  }

  @postgres %Ash.Dsl.Section{
    name: :postgres,
    describe: """
    Postgres data layer configuration
    """,
    sections: [
      @manage_tenant,
      @references,
      @check_constraints
    ],
    modules: [
      :repo
    ],
    examples: [
      """
      postgres do
        repo MyApp.Repo
        table "organizations"
      end
      """
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
      unique_index_names: [
        type: :any,
        default: [],
        doc: """
        A list of unique index names that could raise errors, or an mfa to a function that takes a changeset
        and returns the list. Must be in the format `{[:affected, :keys], "name_of_constraint"}` or `{[:affected, :keys], "name_of_constraint", "custom error message"}`
        """
      ],
      foreign_key_names: [
        type: :any,
        default: [],
        doc: """
        A list of foreign keys that could raise errors, or an mfa to a function that takes a changeset and returns the list.
        Must be in the format `{:key, "name_of_constraint"}` or `{:key, "name_of_constraint", "custom error message"}`
        """
      ],
      table: [
        type: :string,
        doc:
          "The table to store and read the resource from. Required unless `polymorphic?` is true."
      ],
      polymorphic?: [
        type: :boolean,
        default: false,
        doc: """
        Declares this resource as polymorphic.

        Polymorphic resources cannot be read or updated unless the table is provided in the query/changeset context.

        For example:

            PolymorphicResource
            |> Ash.Query.set_context(%{data_layer: %{table: "table"}})
            |> MyApi.read!()

        When relating to polymorphic resources, you'll need to use the `context` option on relationships,
        e.g

            belongs_to :polymorphic_association, PolymorphicResource,
              context: %{data_layer: %{table: "table"}}
        """
      ]
    ]
  }

  alias Ash.Filter
  alias Ash.Query.{BooleanExpression, Not, Ref}

  alias Ash.Query.Function.{Ago, Contains}
  alias Ash.Query.Operator.IsNil

  alias AshPostgres.Functions.{Fragment, TrigramSimilarity, Type}

  import AshPostgres, only: [repo: 1]

  @behaviour Ash.DataLayer

  @sections [@postgres]

  @moduledoc """
  A postgres data layer that levereges Ecto's postgres capabilities.

  # Table of Contents
  #{Ash.Dsl.Extension.doc_index(@sections)}

  #{Ash.Dsl.Extension.doc(@sections)}
  """

  use Ash.Dsl.Extension,
    sections: @sections,
    transformers: [
      AshPostgres.Transformers.VerifyRepo,
      AshPostgres.Transformers.EnsureTableOrPolymorphic
    ]

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
    data_layer = Ash.DataLayer.data_layer(resource)
    other_data_layer = Ash.DataLayer.data_layer(other_resource)
    data_layer == other_data_layer and repo(data_layer) == repo(other_data_layer)
  end

  def can?(resource, {:lateral_join, other_resource}) do
    data_layer = Ash.DataLayer.data_layer(resource)
    other_data_layer = Ash.DataLayer.data_layer(other_resource)
    data_layer == other_data_layer and repo(data_layer) == repo(other_data_layer)
  end

  def can?(_, :boolean_filter), do: true
  def can?(_, {:aggregate, :count}), do: true
  def can?(_, {:aggregate, :sum}), do: true
  def can?(_, :aggregate_filter), do: true
  def can?(_, :aggregate_sort), do: true
  def can?(_, :create), do: true
  def can?(_, :select), do: true
  def can?(_, :read), do: true
  def can?(_, :update), do: true
  def can?(_, :destroy), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  def can?(_, :offset), do: true
  def can?(_, :multitenancy), do: true
  def can?(_, {:filter_expr, _}), do: true
  def can?(_, :nested_expressions), do: true
  def can?(_, {:query_aggregate, :count}), do: true
  def can?(_, :sort), do: true
  def can?(_, :distinct), do: true
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
    AshPostgres.table(resource) || ""
  end

  @impl true
  def set_context(resource, data_layer_query, context) do
    if context[:data_layer][:table] do
      {:ok,
       %{
         data_layer_query
         | from: %{data_layer_query.from | source: {context[:data_layer][:table], resource}}
       }}
    else
      {:ok, data_layer_query}
    end
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
    if AshPostgres.polymorphic?(resource) && no_table?(query) do
      raise_table_error!(resource, :read)
    else
      {:ok, repo(resource).all(query, repo_opts(query))}
    end
  end

  defp no_table?(%{from: %{source: {"", _}}}), do: true
  defp no_table?(_), do: false

  defp repo_opts(%Ash.Changeset{tenant: tenant, resource: resource}) do
    repo_opts(%{tenant: tenant, resource: resource})
  end

  defp repo_opts(%{tenant: tenant, resource: resource}) when not is_nil(tenant) do
    if Ash.Resource.Info.multitenancy_strategy(resource) == :context do
      [prefix: tenant]
    else
      []
    end
  end

  defp repo_opts(_), do: []

  @impl true
  def functions(resource) do
    config = repo(resource).config()

    functions = [AshPostgres.Functions.Type, AshPostgres.Functions.Fragment]

    if "pg_trgm" in (config[:installed_extensions] || []) do
      functions ++
        [
          AshPostgres.Functions.TrigramSimilarity
        ]
    else
      functions
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

    source_resource
    |> Ash.Query.new()
    |> Ash.Query.data_layer_query()
    |> case do
      {:ok, data_layer_query} ->
        from(source in data_layer_query,
          as: :source_record,
          where: field(source, ^source_field) in ^source_values,
          inner_lateral_join: destination in ^subquery,
          on: field(source, ^source_field) == field(destination, ^destination_field),
          select: destination
        )

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def resource_to_query(resource, _),
    do: Ecto.Queryable.to_query({AshPostgres.table(resource) || "", resource})

  @impl true
  def create(resource, changeset) do
    changeset.data
    |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource, changeset)))
    |> ecto_changeset(changeset, :create)
    |> repo(resource).insert(repo_opts(changeset))
    |> handle_errors()
    |> case do
      {:ok, result} ->
        maybe_create_tenant!(resource, result)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_create_tenant!(resource, result) do
    if AshPostgres.manage_tenant_create?(resource) do
      tenant_name = tenant_name(resource, result)

      AshPostgres.MultiTenancy.create_tenant!(tenant_name, repo(resource))
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

  defp handle_errors({:error, %Ecto.Changeset{errors: errors}}) do
    {:error, Enum.map(errors, &to_ash_error/1)}
  end

  defp handle_errors({:ok, val}), do: {:ok, val}

  defp to_ash_error({field, {message, vars}}) do
    Ash.Error.Changes.InvalidAttribute.exception(field: field, message: message, vars: vars)
  end

  defp ecto_changeset(record, changeset, type) do
    ecto_changeset =
      record
      |> set_table(changeset, type)
      |> Ecto.Changeset.change(changeset.attributes)
      |> add_configured_foreign_key_constraints(record.__struct__)
      |> add_unique_indexes(record.__struct__, changeset.tenant, changeset)
      |> add_check_constraints(record.__struct__)

    case type do
      :create ->
        ecto_changeset
        |> add_my_foreign_key_constraints(record.__struct__)

      type when type in [:upsert, :update] ->
        ecto_changeset
        |> add_my_foreign_key_constraints(record.__struct__)
        |> add_related_foreign_key_constraints(record.__struct__)

      :delete ->
        ecto_changeset
        |> add_related_foreign_key_constraints(record.__struct__)
    end
  end

  defp set_table(record, changeset, operation) do
    if AshPostgres.polymorphic?(record.__struct__) do
      table = changeset.context[:data_layer][:table] || AshPostgres.table(record.__struct)

      if table do
        Ecto.put_meta(record, source: table)
      else
        raise_table_error!(changeset.resource, operation)
      end
    else
      record
    end
  end

  defp add_check_constraints(changeset, resource) do
    resource
    |> AshPostgres.check_constraints()
    |> Enum.reduce(changeset, fn constraint, changeset ->
      constraint.attribute
      |> List.wrap()
      |> Enum.reduce(changeset, fn attribute, changeset ->
        Ecto.Changeset.check_constraint(changeset, attribute,
          name: constraint.name,
          message: constraint.message || "is invalid"
        )
      end)
    end)
  end

  defp add_related_foreign_key_constraints(changeset, resource) do
    # TODO: this doesn't guarantee us to get all of them, because if something is related to this
    # schema and there is no back-relation, then this won't catch it's foreign key constraints
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.map(& &1.destination)
    |> Enum.uniq()
    |> Enum.flat_map(fn related ->
      related
      |> Ash.Resource.Info.relationships()
      |> Enum.filter(&(&1.destination == resource))
      |> Enum.map(&Map.take(&1, [:source, :source_field, :destination_field]))
    end)
    |> Enum.uniq()
    |> Enum.reduce(changeset, fn %{
                                   source: source,
                                   source_field: source_field,
                                   destination_field: destination_field
                                 },
                                 changeset ->
      Ecto.Changeset.foreign_key_constraint(changeset, destination_field,
        name: "#{AshPostgres.table(source)}_#{source_field}_fkey",
        message: "would leave records behind"
      )
    end)
  end

  defp add_my_foreign_key_constraints(changeset, resource) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.reduce(changeset, &Ecto.Changeset.foreign_key_constraint(&2, &1.source_field))
  end

  defp add_configured_foreign_key_constraints(changeset, resource) do
    resource
    |> AshPostgres.foreign_key_names()
    |> case do
      {m, f, a} -> List.wrap(apply(m, f, [changeset | a]))
      value -> List.wrap(value)
    end
    |> Enum.reduce(changeset, fn
      {key, name}, changeset ->
        Ecto.Changeset.foreign_key_constraint(changeset, key, name: name)

      {key, name, message}, changeset ->
        Ecto.Changeset.foreign_key_constraint(changeset, key, name: name, message: message)
    end)
  end

  defp add_unique_indexes(changeset, resource, tenant, ash_changeset) do
    changeset =
      resource
      |> Ash.Resource.Info.identities()
      |> Enum.reduce(changeset, fn identity, changeset ->
        name =
          if tenant do
            "#{tenant}_#{table(resource, ash_changeset)}_#{identity.name}_unique_index"
          else
            "#{table(resource, ash_changeset)}_#{identity.name}_unique_index"
          end

        opts =
          if Map.get(identity, :message) do
            [name: name, message: identity.message]
          else
            [name: name]
          end

        Ecto.Changeset.unique_constraint(changeset, identity.keys, opts)
      end)

    names =
      resource
      |> AshPostgres.unique_index_names()
      |> case do
        {m, f, a} -> List.wrap(apply(m, f, [changeset | a]))
        value -> List.wrap(value)
      end

    names = [
      {Ash.Resource.Info.primary_key(resource), table(resource, ash_changeset) <> "_pkey"} | names
    ]

    Enum.reduce(names, changeset, fn
      {keys, name}, changeset ->
        Ecto.Changeset.unique_constraint(changeset, List.wrap(keys), name: name)

      {keys, name, message}, changeset ->
        Ecto.Changeset.unique_constraint(changeset, List.wrap(keys), name: name, message: message)
    end)
  end

  @impl true
  def upsert(resource, changeset) do
    repo_opts =
      changeset
      |> repo_opts()
      |> Keyword.put(:on_conflict, {:replace, Map.keys(changeset.attributes)})
      |> Keyword.put(:conflict_target, Ash.Resource.Info.primary_key(resource))

    if AshPostgres.manage_tenant_update?(resource) do
      {:error, "Cannot currently upsert a resource that owns a tenant"}
    else
      changeset.data
      |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource, changeset)))
      |> ecto_changeset(changeset, :upsert)
      |> repo(resource).insert(repo_opts)
      |> handle_errors()
    end
  end

  @impl true
  def update(resource, changeset) do
    changeset.data
    |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource, changeset)))
    |> ecto_changeset(changeset, :update)
    |> repo(resource).update(repo_opts(changeset))
    |> handle_errors()
    |> case do
      {:ok, result} ->
        maybe_update_tenant(resource, changeset, result)

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def destroy(resource, %{data: record} = changeset) do
    record
    |> ecto_changeset(changeset, :delete)
    |> repo(resource).delete(repo_opts(changeset))
    |> case do
      {:ok, _record} ->
        :ok

      {:error, error} ->
        handle_errors({:error, error})
    end
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

  @impl true
  def select(query, select, resource) do
    query = default_bindings(query, resource)

    {:ok,
     from(row in query,
       select: struct(row, ^select)
     )}
  end

  @impl true
  def distinct(query, distinct_on, resource) do
    query = default_bindings(query, resource)

    query =
      query
      |> default_bindings(resource)
      |> Map.update!(:distinct, fn distinct ->
        distinct =
          distinct ||
            %Ecto.Query.QueryExpr{
              expr: []
            }

        expr =
          Enum.map(distinct_on, fn distinct_on_field ->
            binding =
              case Map.fetch(query.__ash_bindings__.aggregates, distinct_on_field) do
                {:ok, binding} ->
                  binding

                :error ->
                  0
              end

            {:asc, {{:., [], [{:&, [], [binding]}, distinct_on_field]}, [], []}}
          end)

        %{distinct | expr: distinct.expr ++ expr}
      end)

    {:ok, query}
  end

  defp sanitize_sort(sort) do
    sort
    |> List.wrap()
    |> Enum.map(fn
      {sort, :asc_nils_last} -> {:asc_nulls_last, sort}
      {sort, :asc_nils_first} -> {:asc_nulls_first, sort}
      {sort, :desc_nils_last} -> {:desc_nulls_last, sort}
      {sort, :desc_nils_first} -> {:desc_nulls_first, sort}
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

  # For consistency's sake, this logic was removed.
  # We can revisit it sometime though.
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

  @impl true
  def add_aggregate(query, aggregate, _resource) do
    resource = aggregate.resource
    query = default_bindings(query, resource)

    {query, binding} =
      case get_binding(resource, aggregate.relationship_path, query, :aggregate) do
        nil ->
          relationship = Ash.Resource.Info.relationship(resource, aggregate.relationship_path)
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
    accessed = {{:., [], [{:&, [], [binding]}, aggregate.name]}, [], []}

    field =
      {:type, [],
       [
         accessed,
         Ash.Type.ecto_type(aggregate.type)
       ]}

    field_with_default =
      if is_nil(aggregate.default_value) do
        field
      else
        {:coalesce, [],
         [
           field,
           {:type, [],
            [
              aggregate.default_value,
              Ash.Type.ecto_type(aggregate.type)
            ]}
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
    accessed = {{:., [], [{:&, [], [binding]}, aggregate.name]}, [], []}

    field =
      {:type, [],
       [
         accessed,
         Ash.Type.ecto_type(aggregate.type)
       ]}

    field_with_default =
      if is_nil(aggregate.default_value) do
        field
      else
        {:coalesce, [],
         [
           field,
           {:type, [],
            [
              aggregate.default_value,
              Ash.Type.ecto_type(aggregate.type)
            ]}
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
                Ash.Resource.Info.related(resource, aggregate.relationship_path)
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

  defp order_to_postgres_order(dir) do
    case dir do
      :asc -> nil
      :asc_nils_last -> " ASC NULLS LAST"
      :asc_nils_first -> " ASC NULLS FIRST"
      :desc -> " DESC"
      :desc_nils_last -> " DESC NULLS LAST"
      :desc_nils_first -> " DESC NULLS FIRST"
    end
  end

  defp add_subquery_aggregate_select(query, %{kind: kind} = aggregate, _resource)
       when kind in [:first, :list] do
    query = default_bindings(query, aggregate.resource)
    key = aggregate.field
    type = Ash.Type.ecto_type(aggregate.type)

    field =
      if aggregate.query && aggregate.query.sort && aggregate.query.sort != [] do
        sort_expr =
          aggregate.query.sort
          |> Enum.map(fn {sort, order} ->
            case order_to_postgres_order(order) do
              nil ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}]

              order ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}, raw: order]
            end
          end)
          |> Enum.intersperse(raw: ", ")
          |> List.flatten()

        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: " ORDER BY "
         ] ++
           sort_expr ++ [raw: ")"]}
      else
        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: ")"
         ]}
      end

    {params, filtered} =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
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

    casted =
      if kind == :first do
        {:type, [],
         [
           {:fragment, [],
            [
              raw: "(",
              expr: filtered,
              raw: ")[1]"
            ]},
           type
         ]}
      else
        {:type, [],
         [
           filtered,
           {:array, type}
         ]}
      end

    new_expr = {:merge, [], [query.select.expr, {:%{}, [], [{aggregate.name, casted}]}]}

    %{query | select: %{query.select | expr: new_expr, params: params}}
  end

  defp add_subquery_aggregate_select(query, %{kind: :list} = aggregate, _resource) do
    query = default_bindings(query, aggregate.resource)
    key = aggregate.field
    type = Ash.Type.ecto_type(aggregate.type)

    field =
      if aggregate.query && aggregate.query.sort && aggregate.query.sort != [] do
        sort_expr =
          aggregate.query.sort
          |> Enum.map(fn {sort, order} ->
            case order_to_postgres_order(order) do
              nil ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}]

              order ->
                [expr: {{:., [], [{:&, [], [0]}, sort]}, [], []}, raw: order]
            end
          end)
          |> Enum.intersperse(raw: ", ")
          |> List.flatten()

        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: " ORDER BY "
         ] ++
           sort_expr ++ [raw: ")"]}
      else
        {:fragment, [],
         [
           raw: "array_agg(",
           expr: {{:., [], [{:&, [], [0]}, key]}, [], []},
           raw: ")"
         ]}
      end

    {params, filtered} =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
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

    cast = {:type, [], [filtered, {:array, type}]}

    new_expr = {:merge, [], [query.select.expr, {:%{}, [], [{aggregate.name, cast}]}]}

    %{query | select: %{query.select | expr: new_expr, params: params}}
  end

  defp add_subquery_aggregate_select(query, %{kind: kind} = aggregate, resource)
       when kind in [:count, :sum] do
    query = default_bindings(query, aggregate.resource)
    key = aggregate.field || List.first(Ash.Resource.Info.primary_key(resource))
    type = Ash.Type.ecto_type(aggregate.type)

    field = {kind, [], [{{:., [], [{:&, [], [0]}, key]}, [], []}]}

    {params, filtered} =
      if aggregate.query && aggregate.query.filter &&
           not match?(%Ash.Filter{expression: nil}, aggregate.query.filter) do
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
    relationship = Ash.Resource.Info.relationship(resource, relationship)

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
        distinct: ^Ash.Resource.Info.primary_key(relationship.destination)
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

  defp split_and_statements(%BooleanExpression{op: :and, left: left, right: right}) do
    split_and_statements(left) ++ split_and_statements(right)
  end

  defp split_and_statements(%Not{expression: %Not{expression: expression}}) do
    split_and_statements(expression)
  end

  defp split_and_statements(%Not{
         expression: %BooleanExpression{op: :or, left: left, right: right}
       }) do
    split_and_statements(%BooleanExpression{
      op: :and,
      left: %Not{expression: left},
      right: %Not{expression: right}
    })
  end

  defp split_and_statements(other), do: [other]

  defp filter_to_expr(expr, bindings, params, embedded? \\ false, type \\ nil)

  defp filter_to_expr(%Filter{expression: expression}, bindings, params, embedded?, type) do
    filter_to_expr(expression, bindings, params, embedded?, type)
  end

  # A nil filter means "everything"
  defp filter_to_expr(nil, _, _, _, _), do: {[], true}
  # A true filter means "everything"
  defp filter_to_expr(true, _, _, _, _), do: {[], true}
  # A false filter means "nothing"
  defp filter_to_expr(false, _, _, _, _), do: {[], false}

  defp filter_to_expr(expression, bindings, params, embedded?, type) do
    do_filter_to_expr(expression, bindings, params, embedded?, type)
  end

  defp do_filter_to_expr(expr, bindings, params, embedded?, type \\ nil)

  defp do_filter_to_expr(
         %BooleanExpression{op: op, left: left, right: right},
         bindings,
         params,
         embedded?,
         _type
       ) do
    {params, left_expr} = do_filter_to_expr(left, bindings, params, embedded?)
    {params, right_expr} = do_filter_to_expr(right, bindings, params, embedded?)
    {params, {op, [], [left_expr, right_expr]}}
  end

  defp do_filter_to_expr(%Not{expression: expression}, bindings, params, embedded?, _type) do
    {params, new_expression} = do_filter_to_expr(expression, bindings, params, embedded?)
    {params, {:not, [], [new_expression]}}
  end

  defp do_filter_to_expr(
         %TrigramSimilarity{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         params,
         embedded?,
         _type
       ) do
    {params, arg1} = do_filter_to_expr(arg1, bindings, params, pred_embedded? || embedded?)
    {params, arg2} = do_filter_to_expr(arg2, bindings, params, pred_embedded? || embedded?)

    {params, {:fragment, [], [raw: "similarity(", expr: arg1, raw: ", ", expr: arg2, raw: ")"]}}
  end

  defp do_filter_to_expr(
         %Type{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         params,
         embedded?,
         _type
       )
       when pred_embedded? or embedded? do
    {params, arg1} = do_filter_to_expr(arg1, bindings, params, true)
    {params, arg2} = do_filter_to_expr(arg2, bindings, params, true)

    case maybe_ecto_type(arg2) do
      nil ->
        {params, {:type, [], [arg1, arg2]}}

      type ->
        case arg1 do
          %{__predicate__?: _} ->
            {params, {:type, [], [arg1, arg2]}}

          value ->
            {params, %Ecto.Query.Tagged{value: value, type: type}}
        end
    end
  end

  defp do_filter_to_expr(
         %Type{arguments: [arg1, arg2], embedded?: pred_embedded?},
         bindings,
         params,
         embedded?,
         _type
       ) do
    {params, arg1} = do_filter_to_expr(arg1, bindings, params, pred_embedded? || embedded?)
    {params, arg2} = do_filter_to_expr(arg2, bindings, params, pred_embedded? || embedded?)

    arg2 = maybe_ecto_type(arg2)

    {params, {:type, [], [arg1, arg2]}}
  end

  defp do_filter_to_expr(
         %Fragment{arguments: arguments, embedded?: pred_embedded?},
         bindings,
         params,
         embedded?,
         _type
       ) do
    {params, fragment_data} =
      Enum.reduce(arguments, {params, []}, fn
        {:raw, str}, {params, fragment_data} ->
          {params, fragment_data ++ [{:raw, str}]}

        {:expr, expr}, {params, fragment_data} ->
          {params, expr} = do_filter_to_expr(expr, bindings, params, pred_embedded? || embedded?)
          {params, fragment_data ++ [{:expr, expr}]}
      end)

    {params, {:fragment, [], fragment_data}}
  end

  defp do_filter_to_expr(
         %IsNil{left: left, right: right, embedded?: pred_embedded?},
         bindings,
         params,
         embedded?,
         _type
       ) do
    {params, left_expr} = do_filter_to_expr(left, bindings, params, pred_embedded? || embedded?)
    {params, right_expr} = do_filter_to_expr(right, bindings, params, pred_embedded? || embedded?)

    {params,
     {:==, [],
      [
        {:is_nil, [], [left_expr]},
        right_expr
      ]}}
  end

  defp do_filter_to_expr(
         %Ago{arguments: [left, right], embedded?: _pred_embedded?},
         _bindings,
         params,
         _embedded?,
         _type
       )
       when is_integer(left) and (is_binary(right) or is_atom(right)) do
    {params ++ [{DateTime.utc_now(), {:param, :any_datetime}}],
     {:datetime_add, [], [{:^, [], [Enum.count(params)]}, left * -1, to_string(right)]}}
  end

  defp do_filter_to_expr(
         %Contains{arguments: [left, %Ash.CiString{} = right], embedded?: pred_embedded?},
         bindings,
         params,
         embedded?,
         type
       ) do
    do_filter_to_expr(
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "strpos(",
          expr: left,
          raw: "::citext, ",
          expr: right,
          raw: ") > 0"
        ]
      },
      bindings,
      params,
      embedded?,
      type
    )
  end

  defp do_filter_to_expr(
         %Contains{arguments: [left, right], embedded?: pred_embedded?},
         bindings,
         params,
         embedded?,
         type
       ) do
    do_filter_to_expr(
      %Fragment{
        embedded?: pred_embedded?,
        arguments: [
          raw: "strpos(",
          expr: left,
          raw: ", ",
          expr: right,
          raw: ") > 0"
        ]
      },
      bindings,
      params,
      embedded?,
      type
    )
  end

  defp do_filter_to_expr(
         %mod{
           __predicate__?: _,
           left: left,
           right: right,
           embedded?: pred_embedded?,
           operator: op
         },
         bindings,
         params,
         embedded?,
         _type
       ) do
    [left_type, right_type] = determine_types(mod, [left, right])

    {params, left_expr} =
      do_filter_to_expr(left, bindings, params, pred_embedded? || embedded?, left_type)

    {params, right_expr} =
      do_filter_to_expr(right, bindings, params, pred_embedded? || embedded?, right_type)

    {params,
     {op, [],
      [
        left_expr,
        right_expr
      ]}}
  end

  defp do_filter_to_expr(
         %Ref{attribute: %{name: name}} = ref,
         bindings,
         params,
         _embedded?,
         _type
       ) do
    {params, {{:., [], [{:&, [], [ref_binding(ref, bindings)]}, name]}, [], []}}
  end

  defp do_filter_to_expr({:embed, other}, _bindings, params, _true, _type) do
    {params, other}
  end

  defp do_filter_to_expr(%Ash.CiString{string: string}, bindings, params, embedded?, type) do
    do_filter_to_expr(
      %Fragment{
        embedded?: embedded?,
        arguments: [
          raw: "",
          expr: string,
          raw: "::citext"
        ]
      },
      bindings,
      params,
      embedded?,
      type
    )
  end

  defp do_filter_to_expr(%MapSet{} = mapset, bindings, params, embedded?, type) do
    do_filter_to_expr(Enum.to_list(mapset), bindings, params, embedded?, type)
  end

  defp do_filter_to_expr(other, _bindings, params, true, _type) do
    {params, other}
  end

  defp do_filter_to_expr(value, _bindings, params, false, type) do
    type = type || :any
    value = last_ditch_cast(value, type)

    {params ++ [{value, type}], {:^, [], [Enum.count(params)]}}
  end

  defp maybe_ecto_type({:array, type}), do: {:array, maybe_ecto_type(type)}

  defp maybe_ecto_type(type) when is_atom(type) do
    if Ash.Type.ash_type?(type) do
      Ash.Type.ecto_type(type)
    end
  end

  defp maybe_ecto_type(_type), do: nil

  defp last_ditch_cast(value, :string) when is_atom(value) do
    to_string(value)
  end

  defp last_ditch_cast(value, _type) do
    value
  end

  defp determine_types(mod, values) do
    mod.types()
    |> Enum.map(fn types ->
      case types do
        :same ->
          types =
            for _ <- values do
              :same
            end

          closest_fitting_type(types, values)

        :any ->
          for _ <- values do
            :any
          end

        types ->
          closest_fitting_type(types, values)
      end
    end)
    |> Enum.min_by(fn types ->
      types
      |> Enum.map(&vagueness/1)
      |> Enum.sum()
    end)
  end

  defp closest_fitting_type(types, values) do
    types_with_values = Enum.zip(types, values)

    types_with_values
    |> fill_in_known_types()
    |> clarify_types()
  end

  defp clarify_types(types) do
    basis =
      types
      |> Enum.map(&elem(&1, 0))
      |> Enum.min_by(&vagueness(&1))

    Enum.map(types, fn {type, _value} ->
      replace_same(type, basis)
    end)
  end

  defp replace_same({:in, type}, basis) do
    {:in, replace_same(type, basis)}
  end

  defp replace_same(:same, :same) do
    :any
  end

  defp replace_same(:same, {:in, :same}) do
    {:in, :any}
  end

  defp replace_same(:same, basis) do
    basis
  end

  defp replace_same(other, _basis) do
    other
  end

  defp fill_in_known_types(types) do
    Enum.map(types, &fill_in_known_type/1)
  end

  defp fill_in_known_type({vague_type, %Ref{attribute: %{type: type}}} = ref)
       when vague_type in [:any, :same] do
    if Ash.Type.ash_type?(type) do
      {type |> Ash.Type.storage_type() |> array_to_in(), ref}
    else
      {type |> array_to_in(), ref}
    end
  end

  defp fill_in_known_type(
         {{:array, type}, %Ref{attribute: %{type: {:array, type}} = attribute} = ref}
       ) do
    {:in, fill_in_known_type({type, %{ref | attribute: %{attribute | type: type}}})}
  end

  defp fill_in_known_type({type, value}), do: {array_to_in(type), value}

  defp array_to_in({:array, v}), do: {:in, array_to_in(v)}
  defp array_to_in(v), do: v

  defp vagueness({:in, type}), do: vagueness(type)
  defp vagueness(:same), do: 2
  defp vagueness(:any), do: 1
  defp vagueness(_), do: 0

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

  defp table(resource, changeset) do
    changeset.context[:data_layer][:table] || AshPostgres.table(resource)
  end

  defp raise_table_error!(resource, operation) do
    if AshPostgres.polymorphic?(resource) do
      raise """
      Could not determine table for #{operation} on #{inspect(resource)}.

      Polymorphic resources require that the `data_layer[:table]` context is provided.
      See the guide on polymorphic resources for more information.
      """
    else
      raise """
      Could not determine table for #{operation} on #{inspect(resource)}.
      """
    end
  end
end
