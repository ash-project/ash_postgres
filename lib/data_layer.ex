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

  @index %Ash.Dsl.Entity{
    name: :index,
    describe: """
    Add an index to be managed by the migration generator.
    """,
    examples: [
      "index [\"column\", \"column2\"], unique: true, where: \"thing = TRUE\""
    ],
    target: AshPostgres.CustomIndex,
    schema: AshPostgres.CustomIndex.schema(),
    args: [:fields]
  }

  @custom_indexes %Ash.Dsl.Section{
    name: :custom_indexes,
    describe: """
    A section for configuring indexes to be created by the migration generator.

    In general, prefer to use `identities` for simple unique constraints. This is a tool to allow
    for declaring more complex indexes.
    """,
    examples: [
      """
      custom_indexes do
        index [:column1, :column2], unique: true, where: "thing = TRUE"
      end
      """
    ],
    entities: [
      @index
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
      @custom_indexes,
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
      migration_types: [
        type: :keyword_list,
        default: [],
        doc:
          "A keyword list of attribute names to the ecto migration type that should be used for that attribute. Only necessary if you need to override the defaults."
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

        Note that this is *not* used to rename the unique indexes created from `identities`.
        Use `identity_index_names` for that. This is used to tell ash_postgres about unique indexes that
        exist in the database that it didn't create.
        """
      ],
      exclusion_constraint_names: [
        type: :any,
        default: [],
        doc: """
        A list of exclusion constraint names that could raise errors. Must be in the format `{:affected_key, "name_of_constraint"}` or `{:affected_key, "name_of_constraint", "custom error message"}`
        """
      ],
      identity_index_names: [
        type: :any,
        default: [],
        doc: """
        A keyword list of identity names to the unique index name that they should use when being managed by the migration
        generator.
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
  alias Ash.Query.{BooleanExpression, Not}

  import AshPostgres, only: [repo: 1]

  @behaviour Ash.DataLayer

  @sections [@postgres]

  @moduledoc """
  A postgres data layer that leverages Ecto's postgres capabilities.
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
    data_layer == other_data_layer and repo(resource) == repo(other_resource)
  end

  def can?(resource, {:lateral_join, resources}) do
    repo = repo(resource)
    data_layer = Ash.DataLayer.data_layer(resource)

    data_layer == __MODULE__ &&
      Enum.all?(resources, fn resource ->
        Ash.DataLayer.data_layer(resource) == data_layer && repo(resource) == repo
      end)
  end

  def can?(_, :boolean_filter), do: true
  def can?(_, {:aggregate, :count}), do: true
  def can?(_, {:aggregate, :sum}), do: true
  def can?(_, {:aggregate, :first}), do: true
  def can?(_, {:aggregate, :list}), do: true
  def can?(_, :aggregate_filter), do: true
  def can?(_, :aggregate_sort), do: true
  def can?(_, :expression_calculation), do: true
  def can?(_, :expression_calculation_sort), do: true
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
    data_layer_query =
      if context[:data_layer][:table] do
        %{
          data_layer_query
          | from: %{data_layer_query.from | source: {context[:data_layer][:table], resource}}
        }
      else
        data_layer_query
      end

    data_layer_query =
      data_layer_query
      |> default_bindings(resource, context)

    {:ok, data_layer_query}
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

  defp repo_opts(%{tenant: tenant, resource: resource} = changeset) when not is_nil(tenant) do
    if Ash.Resource.Info.multitenancy_strategy(resource) == :context do
      [prefix: tenant]
    else
      []
    end
    |> add_timeout(changeset)
  end

  defp repo_opts(_), do: []

  defp add_timeout(opts, %{timeout: timeout}) when not is_nil(timeout) do
    Keyword.put(opts, :timeout, timeout)
  end

  defp add_timeout(opts, _), do: opts

  defp lateral_join_repo_opts(%{tenant: tenant} = query, resource) when not is_nil(tenant) do
    if Ash.Resource.Info.multitenancy_strategy(resource) == :context do
      [prefix: tenant]
    else
      []
    end
    |> add_timeout(query)
  end

  defp lateral_join_repo_opts(_, _), do: []

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
        &AshPostgres.Aggregate.add_subquery_aggregate_select(&2, &1, resource)
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
        destination_resource,
        path
      ) do
    case lateral_join_query(
           query,
           root_data,
           path
         ) do
      {:ok, lateral_join_query} ->
        source_resource =
          path
          |> Enum.at(0)
          |> elem(0)
          |> Map.get(:resource)

        subquery = from(row in subquery(lateral_join_query), select: %{})

        query =
          Enum.reduce(
            aggregates,
            subquery,
            &AshPostgres.Aggregate.add_subquery_aggregate_select(&2, &1, destination_resource)
          )

        {:ok, repo(source_resource).one(query, lateral_join_repo_opts(query, source_resource))}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def run_query_with_lateral_join(
        query,
        root_data,
        _destination_resource,
        path
      ) do
    source_query =
      path
      |> Enum.at(0)
      |> elem(0)

    case lateral_join_query(
           query,
           root_data,
           path
         ) do
      {:ok, query} ->
        source_resource =
          path
          |> Enum.at(0)
          |> elem(0)
          |> Map.get(:resource)

        {:ok,
         repo(source_resource).all(query, lateral_join_repo_opts(source_query, source_resource))}

      {:error, error} ->
        {:error, error}
    end
  end

  defp lateral_join_query(
         query,
         root_data,
         [{source_query, source_field, destination_field, relationship}]
       ) do
    source_values = Enum.map(root_data, &Map.get(&1, source_field))
    source_query = Ash.Query.new(source_query)

    subquery =
      if query.windows[:order] do
        subquery(
          from(destination in query,
            select_merge: %{__order__: over(row_number(), :order)},
            where:
              field(destination, ^destination_field) ==
                field(parent_as(^0), ^source_field)
          )
          |> set_subquery_prefix(source_query, relationship.destination)
        )
      else
        subquery(
          from(destination in query,
            where:
              field(destination, ^destination_field) ==
                field(parent_as(^0), ^source_field)
          )
          |> set_subquery_prefix(source_query, relationship.destination)
        )
      end

    source_query.resource
    |> Ash.Query.set_context(%{:data_layer => source_query.context[:data_layer]})
    |> Ash.Query.set_tenant(source_query.tenant)
    |> set_lateral_join_prefix(query)
    |> case do
      %{valid?: true} = query ->
        Ash.Query.data_layer_query(query)

      query ->
        {:error, query}
    end
    |> case do
      {:ok, data_layer_query} ->
        if query.windows[:order] do
          {:ok,
           from(source in data_layer_query,
             where: field(source, ^source_field) in ^source_values,
             inner_lateral_join: destination in ^subquery,
             on: field(source, ^source_field) == field(destination, ^destination_field),
             order_by: destination.__order__,
             select: destination,
             distinct: true
           )}
        else
          {:ok,
           from(source in data_layer_query,
             where: field(source, ^source_field) in ^source_values,
             inner_lateral_join: destination in ^subquery,
             on: field(source, ^source_field) == field(destination, ^destination_field),
             select: destination,
             distinct: true
           )}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp lateral_join_query(
         query,
         root_data,
         [
           {source_query, source_field, source_field_on_join_table, relationship},
           {through_resource, destination_field_on_join_table, destination_field,
            through_relationship}
         ]
       ) do
    source_query = Ash.Query.new(source_query)
    source_values = Enum.map(root_data, &Map.get(&1, source_field))

    through_resource
    |> Ash.Query.new()
    |> Ash.Query.set_context(through_relationship.context)
    |> Ash.Query.do_filter(through_relationship.filter)
    |> Ash.Query.sort(through_relationship.sort)
    |> Ash.Query.set_tenant(source_query.tenant)
    |> set_lateral_join_prefix(query)
    |> case do
      %{valid?: true} = query ->
        Ash.Query.data_layer_query(query)

      query ->
        {:error, query}
    end
    |> case do
      {:ok, through_query} ->
        source_query.resource
        |> Ash.Query.new()
        |> Ash.Query.set_context(relationship.context)
        |> Ash.Query.set_context(%{:data_layer => source_query.context[:data_layer]})
        |> set_lateral_join_prefix(query)
        |> Ash.Query.do_filter(relationship.filter)
        |> case do
          %{valid?: true} = query ->
            Ash.Query.data_layer_query(query)

          query ->
            {:error, query}
        end
        |> case do
          {:ok, data_layer_query} ->
            if query.windows[:order] do
              subquery =
                subquery(
                  from(
                    destination in query,
                    select_merge: %{__order__: over(row_number(), :order)},
                    join:
                      through in ^set_subquery_prefix(
                        through_query,
                        source_query,
                        relationship.through
                      ),
                    as: ^1,
                    on:
                      field(through, ^destination_field_on_join_table) ==
                        field(destination, ^destination_field),
                    where:
                      field(through, ^source_field_on_join_table) ==
                        field(parent_as(^0), ^source_field)
                  )
                  |> set_subquery_prefix(
                    source_query,
                    relationship.destination
                  )
                )

              {:ok,
               from(source in data_layer_query,
                 where: field(source, ^source_field) in ^source_values,
                 inner_lateral_join: destination in ^subquery,
                 select: destination,
                 order_by: destination.__order__,
                 distinct: true
               )}
            else
              subquery =
                subquery(
                  from(
                    destination in query,
                    join:
                      through in ^set_subquery_prefix(
                        through_query,
                        source_query,
                        relationship.through
                      ),
                    as: ^1,
                    on:
                      field(through, ^destination_field_on_join_table) ==
                        field(destination, ^destination_field),
                    where:
                      field(through, ^source_field_on_join_table) ==
                        field(parent_as(^0), ^source_field)
                  )
                  |> set_subquery_prefix(
                    source_query,
                    relationship.destination
                  )
                )

              {:ok,
               from(source in data_layer_query,
                 where: field(source, ^source_field) in ^source_values,
                 inner_lateral_join: destination in ^subquery,
                 select: destination,
                 distinct: true
               )}
            end

          {:error, error} ->
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp set_subquery_prefix(data_layer_query, source_query, resource) do
    config = repo(resource).config()

    if Ash.Resource.Info.multitenancy_strategy(resource) == :context do
      %{
        data_layer_query
        | prefix:
            to_string(
              source_query.tenant || config[:default_prefix] ||
                "public"
            )
      }
    else
      %{
        data_layer_query
        | prefix:
            to_string(
              config[:default_prefix] ||
                "public"
            )
      }
    end
  end

  defp set_lateral_join_prefix(ash_query, query) do
    if Ash.Resource.Info.multitenancy_strategy(ash_query.resource) == :context do
      Ash.Query.set_tenant(ash_query, query.prefix)
    else
      ash_query
    end
  end

  @impl true
  def resource_to_query(resource, _) do
    from(row in {AshPostgres.table(resource) || "", resource}, as: ^0)
  end

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
    Ash.Error.Changes.InvalidAttribute.exception(
      field: field,
      message: message,
      private_vars: vars
    )
  end

  defp ecto_changeset(record, changeset, type) do
    ecto_changeset =
      record
      |> set_table(changeset, type)
      |> Ecto.Changeset.change(changeset.attributes)
      |> add_configured_foreign_key_constraints(record.__struct__)
      |> add_unique_indexes(record.__struct__, changeset)
      |> add_check_constraints(record.__struct__)
      |> add_exclusion_constraints(record.__struct__)

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
      table = changeset.context[:data_layer][:table] || AshPostgres.table(record.__struct__)

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

  defp add_exclusion_constraints(changeset, resource) do
    resource
    |> AshPostgres.exclusion_constraint_names()
    |> Enum.reduce(changeset, fn constraint, changeset ->
      case constraint do
        {key, name} ->
          Ecto.Changeset.exclusion_constraint(changeset, key, name: name)

        {key, name, message} ->
          Ecto.Changeset.exclusion_constraint(changeset, key, name: name, message: message)
      end
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

  defp add_unique_indexes(changeset, resource, ash_changeset) do
    changeset =
      resource
      |> Ash.Resource.Info.identities()
      |> Enum.reduce(changeset, fn identity, changeset ->
        name =
          AshPostgres.identity_index_names(resource)[identity.name] ||
            "#{table(resource, ash_changeset)}_#{identity.name}_index"

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
  def upsert(resource, changeset, keys \\ nil) do
    keys = keys || Ash.Resource.Info.primary_key(resource)
    attributes = Map.keys(changeset.attributes) -- Map.get(changeset, :defaults, []) -- keys

    repo_opts =
      changeset
      |> repo_opts()
      |> Keyword.put(:on_conflict, {:replace, attributes})
      |> Keyword.put(:conflict_target, keys)

    if AshPostgres.manage_tenant_update?(resource) do
      {:error, "Cannot currently upsert a resource that owns a tenant"}
    else
      changeset.data
      |> Map.update!(:__meta__, &Map.put(&1, :source, table(resource, changeset)))
      |> ecto_changeset(changeset, :upsert)
      |> repo(resource).insert(Keyword.put(repo_opts, :returning, true))
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
    AshPostgres.Sort.sort(query, sort, resource)
  end

  @impl true
  def select(query, select, resource) do
    query = default_bindings(query, resource)

    {:ok,
     from(row in query,
       select: struct(row, ^Enum.uniq(select))
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

  @impl true
  def filter(query, %{expression: false}, _resource) do
    impossible_query = from(row in query, where: false)
    {:ok, Map.put(impossible_query, :__impossible__, true)}
  end

  def filter(query, filter, resource) do
    query = default_bindings(query, resource)

    query
    |> AshPostgres.Join.join_all_relationships(filter)
    |> case do
      {:ok, query} ->
        {:ok, add_filter_expression(query, filter)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  def default_bindings(query, resource, context \\ %{}) do
    Map.put_new(query, :__ash_bindings__, %{
      current: Enum.count(query.joins) + 1,
      calculations: %{},
      aggregates: %{},
      aggregate_defs: %{},
      context: context,
      bindings: %{0 => %{path: [], type: :root, source: resource}}
    })
  end

  @impl true
  def add_aggregates(query, aggregates, resource) do
    AshPostgres.Aggregate.add_aggregates(query, aggregates, resource)
  end

  @impl true
  def add_calculations(query, calculations, resource) do
    AshPostgres.Calculation.add_calculations(query, calculations, resource)
  end

  @doc false
  def get_binding(resource, path, %{__ash_bindings__: _} = query, type) do
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

  def get_binding(_, _, _, _), do: nil

  defp add_filter_expression(query, filter) do
    filter
    |> split_and_statements()
    |> Enum.reduce(query, fn filter, query ->
      dynamic = AshPostgres.Expr.dynamic_expr(query, filter, query.__ash_bindings__)

      Ecto.Query.where(query, ^dynamic)
    end)
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

  @doc false
  def add_binding(query, data, additional_bindings \\ 0) do
    current = query.__ash_bindings__.current
    bindings = query.__ash_bindings__.bindings

    new_ash_bindings = %{
      query.__ash_bindings__
      | bindings: Map.put(bindings, current, data),
        current: current + 1 + additional_bindings
    }

    %{query | __ash_bindings__: new_ash_bindings}
  end

  @impl true
  def transaction(resource, func, timeout \\ nil) do
    if timeout do
      repo(resource).transaction(func, timeout: timeout)
    else
      repo(resource).transaction(func)
    end
  end

  @impl true
  def rollback(resource, term) do
    repo(resource).rollback(term)
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
