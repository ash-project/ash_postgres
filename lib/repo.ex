defmodule AshPostgres.Repo do
  @moduledoc """
  Resources that use `AshPostgres.DataLayer` use a `Repo` to access the database.

  This repo is a thin wrapper around an `Ecto.Repo`.

  You can use `Ecto.Repo`'s `init/2` to configure your repo like normal, but
  instead of returning `{:ok, config}`, use `super(config)` to pass the
  configuration to the `AshPostgres.Repo` implementation.

  ## Installed Extensions

  To configure your list of installed extensions, define `installed_extensions/0`

  Extensions can be a string, representing a standard postgres extension, or a module that implements `AshPostgres.CustomExtension`.
  That custom extension will be called to generate migrations that serve a specific purpose.

  Extensions that are relevant to ash_postgres:

  * "ash-functions" - This isn't really an extension, but it expresses that certain functions
    should be added when generating migrations, to support the `||` and `&&` operators in expressions.
  * `"uuid-ossp"` - Sets UUID primary keys defaults in the migration generator
  * `"pg_trgm"` - Makes the `AshPostgres.Functions.TrigramSimilarity` function available
  * "citext" - Allows case insensitive fields to be used
  * `"vector"` - Makes the `AshPostgres.Functions.VectorCosineDistance` function available. See `AshPostgres.Extensions.Vector` for more setup instructions.

  ```
  def installed_extensions() do
    ["pg_trgm", "uuid-ossp", "vector", YourCustomExtension]
  end
  ```

  ## Transaction Hooks

  You can define `on_transaction_begin/1`, which will be invoked whenever a transaction is started for Ash.

  This will be invoked with a map containing a `type` key and metadata.

  ```elixir
  %{type: :create, %{resource: YourApp.YourResource, action: :action}}
  ```

  ## Additional Repo Configuration

  Because an `AshPostgres.Repo` is also an `Ecto.Repo`, it has all of the same callbacks.

  In the `c:Ecto.Repo.init/2` callback, you can configure the following additional items:

  - `:tenant_migrations_path` - The path where your tenant migrations are stored (only relevant for a multitenant implementation)
  - `:snapshots_path` - The path where the resource snapshots for the migration generator are stored.
  """

  @doc "Use this to inform the data layer about what extensions are installed"
  @callback installed_extensions() :: [String.t() | module()]

  @doc "Configure the version of postgres that is being used."
  @callback min_pg_version() :: Version.t()

  @doc """
  Use this to inform the data layer about the oldest potential postgres version it will be run on.

  Must be an integer greater than or equal to 13.

  ## Combining with other tools

  For things like `Fly.Repo`, where you might need to have more fine grained control over the repo module,
  you can use the `define_ecto_repo?: false` option to `use AshPostgres.Repo`.
  """

  @callback on_transaction_begin(reason :: Ash.DataLayer.transaction_reason()) :: term

  @doc "Return a list of all schema names (only relevant for a multitenant implementation)"
  @callback all_tenants() :: [String.t()]
  @doc "The path where your tenant migrations are stored (only relevant for a multitenant implementation)"
  @callback tenant_migrations_path() :: String.t() | nil
  @doc "The path where your migrations are stored"
  @callback migrations_path() :: String.t() | nil
  @doc "The default prefix(postgres schema) to use when building queries"
  @callback default_prefix() :: String.t()

  @doc "Whether or not to create schemas for tables when generating migrations"
  @callback create_schemas_in_migrations?() :: boolean()

  @doc "Whether or not to explicitly start and close a transaction for each action, even if there are no transaction hooks. Defaults to `true`."
  @callback prefer_transaction?() :: boolean

  @doc "Whether or not to explicitly start and close a transaction for each atomic update action, even if there are no transaction hooks. Defaults to `false`."
  @callback prefer_transaction_for_atomic_updates?() :: boolean

  @doc """
  Determine how constraint names are matched when generating errors.

  This is useful if you are using something like citus that creates generated constraint
  names for each node. In that case, for example, you might return a regex that
  matches the name plus digits.
  """
  @callback default_constraint_match_type(
              type :: :custom | :exclusion | :unique | :foreign | :check,
              name :: String.t()
            ) ::
              :exact | :prefix | :suffix | {:regex, Regex.t()}

  @doc "Allows overriding a given migration type for *all* fields, for example if you wanted to always use :timestamptz for :utc_datetime fields"
  @callback override_migration_type(atom) :: atom
  @doc "Should the repo should be created by `mix ash_postgres.create`?"
  @callback create?() :: boolean
  @doc "Should the repo should be dropped by `mix ash_postgres.drop`?"
  @callback drop?() :: boolean

  @doc "Disable atomic actions for this repo"
  @callback disable_atomic_actions?() :: boolean

  @doc "Disable expression errors for this repo"
  @callback disable_expr_error?() :: boolean

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if Keyword.get(opts, :define_ecto_repo?, true) do
        otp_app = opts[:otp_app] || raise("Must configure OTP app")

        use Ecto.Repo,
          adapter: opts[:adapter] || Ecto.Adapters.Postgres,
          otp_app: otp_app
      end

      @behaviour AshPostgres.Repo
      @warn_on_missing_ash_functions Keyword.get(opts, :warn_on_missing_ash_functions?, true)
      @after_compile __MODULE__
      @before_compile AshPostgres.Repo.BeforeCompile
      require Logger

      defoverridable insert: 2, insert: 1, insert!: 2, insert!: 1, transaction: 1, transaction: 2

      def transaction(fun, opts \\ []) do
        super(fun, opts)
      end

      def installed_extensions, do: []
      def tenant_migrations_path, do: nil
      def migrations_path, do: nil
      def create_schemas_in_migrations?, do: true
      def default_prefix, do: "public"
      def override_migration_type(type), do: type
      def create?, do: true
      def drop?, do: true
      def disable_atomic_actions?, do: false
      def disable_expr_error?, do: false

      # default to false in 4.0
      def prefer_transaction?, do: true

      def prefer_transaction_for_atomic_updates?, do: false

      def default_constraint_match_type(_type, _name), do: :exact

      def transaction!(fun) do
        case fun.() do
          {:ok, value} -> value
          {:error, error} -> raise Ash.Error.to_error_class(error)
        end
      end

      def all_tenants do
        raise """
        `#{inspect(__MODULE__)}.all_tenants/0` was called, but was not defined. In order to migrate tenants, you must define this function.
        For example, you might say:

          def all_tenants do
            for org <- MyApp.Accounts.all_organizations!() do
              org.schema
            end
          end
        """
      end

      def init(type, config) do
        new_config =
          config
          |> Keyword.put(:installed_extensions, installed_extensions())
          |> Keyword.put(:tenant_migrations_path, tenant_migrations_path())
          |> Keyword.put(:migrations_path, migrations_path())
          |> Keyword.put(:default_prefix, default_prefix())

        {:ok, new_config}
      end

      def on_transaction_begin(_reason), do: :ok

      # copied from Ecto.Repo
      defp ash_postgres_prepare_opts(operation_name, []),
        do: default_options(operation_name)

      defp ash_postgres_prepare_opts(operation_name, [{key, _} | _rest] = opts)
           when is_atom(key) do
        operation_name
        |> default_options()
        |> Keyword.merge(opts)
      end

      def insert(struct_or_changeset, opts \\ []) do
        struct_or_changeset
        |> to_ecto()
        |> then(fn value ->
          repo = get_dynamic_repo()

          Ecto.Repo.Schema.insert(
            __MODULE__,
            repo,
            value,
            Ecto.Repo.Supervisor.tuplet(repo, ash_postgres_prepare_opts(:insert, opts))
          )
        end)
        |> from_ecto()
      end

      def insert!(struct_or_changeset, opts \\ []) do
        struct_or_changeset
        |> to_ecto()
        |> then(fn value ->
          repo = get_dynamic_repo()

          Ecto.Repo.Schema.insert!(
            __MODULE__,
            repo,
            value,
            Ecto.Repo.Supervisor.tuplet(repo, ash_postgres_prepare_opts(:insert, opts))
          )
        end)
        |> from_ecto()
      end

      def from_ecto({:ok, result}), do: {:ok, from_ecto(result)}
      def from_ecto({:error, _} = other), do: other

      def from_ecto(nil), do: nil

      def from_ecto(value) when is_list(value) do
        Enum.map(value, &from_ecto/1)
      end

      def from_ecto(%Ecto.Changeset{} = changeset) do
        Map.put(changeset, :data, from_ecto(changeset.data))
      end

      def from_ecto(%resource{} = record) do
        if Spark.Dsl.is?(resource, Ash.Resource) do
          empty = struct(resource)

          resource
          |> Ash.Resource.Info.relationships()
          |> Enum.reduce(record, fn relationship, record ->
            case Map.get(record, relationship.name) do
              %Ecto.Association.NotLoaded{} ->
                Map.put(record, relationship.name, Map.get(empty, relationship.name))

              value ->
                Map.put(record, relationship.name, from_ecto(value))
            end
          end)
        else
          record
        end
      end

      def from_ecto(other), do: other

      def to_ecto(nil), do: nil

      def to_ecto(value) when is_list(value) do
        Enum.map(value, &to_ecto/1)
      end

      def to_ecto(%Ecto.Changeset{} = changeset) do
        Map.put(changeset, :data, to_ecto(changeset.data))
      end

      def to_ecto(%resource{} = record) do
        if Spark.Dsl.is?(resource, Ash.Resource) do
          resource
          |> Ash.Resource.Info.relationships()
          |> Enum.reduce(record, fn relationship, record ->
            value =
              case Map.get(record, relationship.name) do
                %Ash.NotLoaded{} ->
                  %Ecto.Association.NotLoaded{
                    __field__: relationship.name,
                    __cardinality__: relationship.cardinality
                  }

                value ->
                  to_ecto(value)
              end

            Map.put(record, relationship.name, value)
          end)
        else
          record
        end
      end

      def to_ecto(other), do: other

      defoverridable init: 2,
                     on_transaction_begin: 1,
                     installed_extensions: 0,
                     all_tenants: 0,
                     default_constraint_match_type: 2,
                     prefer_transaction?: 0,
                     prefer_transaction_for_atomic_updates?: 0,
                     tenant_migrations_path: 0,
                     create_schemas_in_migrations?: 0,
                     migrations_path: 0,
                     default_prefix: 0,
                     override_migration_type: 1,
                     create?: 0,
                     drop?: 0,
                     disable_atomic_actions?: 0,
                     disable_expr_error?: 0

      # We do this switch because `!@warn_on_missing_ash_functions` in the function body triggers
      # a dialyzer error
      if @warn_on_missing_ash_functions do
        def __after_compile__(_, _) do
          if "ash-functions" in installed_extensions() do
            :ok
          else
            IO.warn("""
            AshPostgres: You have not installed the `ash-functions` extension.

            The following features will not be available:

            - atomics (using the `raise_ash_error` function)
            - `string_trim` (using the `ash_trim_whitespace` function)
            - the `||` and `&&` operators (using the `ash_elixir_and` and `ash_elixir_or` functions)

            To address this warning, do one of two things:

            1. add the `"ash-functions"` extension to your `installed_extensions/0` function, and then generate migrations.

                def installed_extensions do
                  ["ash-functions"]
                end

            If you are *not* using the migration generator, but would like to leverage these features, follow the above instructions,
            and then visit the source for `ash_postgres` and copy the latest version of those functions into your own migrations:

            2. disable this warning, by adding the following to your `use` statement:

                use AshPostgres.Repo,
                  ..
                  warn_on_missing_ash_functions?: false

            Keep in mind that if you disable this warning, you will not be able to use the features mentioned above.
            If you are in an environment where you cannot define functions, you will have to use the second option.


            https://github.com/ash-project/ash_postgres/blob/main/lib/migration_generator/ash_functions.ex
            """)
          end
        end
      else
        def __after_compile__(_, _) do
          :ok
        end
      end
    end
  end
end
