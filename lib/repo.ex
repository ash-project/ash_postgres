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
  """

  @doc "Use this to inform the data layer about what extensions are installed"
  @callback installed_extensions() :: [String.t() | module()]

  @doc "Configure the version of postgres that is being used."
  @callback pg_version() :: Version.t()

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
  @doc "Transform a given tenant value into a schema string"
  @callback tenant_to_schema(term()) :: String.t()

  @doc "Allows overriding a given migration type for *all* fields, for example if you wanted to always use :timestamptz for :utc_datetime fields"
  @callback override_migration_type(atom) :: atom

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if Keyword.get(opts, :define_ecto_repo?, true) do
        otp_app = opts[:otp_app] || raise("Must configure OTP app")

        use Ecto.Repo,
          adapter: Ecto.Adapters.Postgres,
          otp_app: otp_app
      end

      @behaviour AshPostgres.Repo

      defoverridable insert: 2, insert: 1, insert!: 2, insert!: 1

      def installed_extensions, do: []
      def tenant_migrations_path, do: nil
      def migrations_path, do: nil
      def default_prefix, do: "public"
      def override_migration_type(type), do: type
      def tenant_to_schema(term), do: to_string(term)

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

      def init(_, config) do
        new_config =
          config
          |> Keyword.put(:installed_extensions, installed_extensions())
          |> Keyword.put(:tenant_migrations_path, tenant_migrations_path())
          |> Keyword.put(:migrations_path, migrations_path())
          |> Keyword.put(:default_prefix, default_prefix())

        {:ok, new_config}
      end

      def on_transaction_begin(_reason), do: :ok

      def insert(struct_or_changeset, opts \\ []) do
        struct_or_changeset
        |> to_ecto()
        |> then(fn value ->
          repo = get_dynamic_repo()

          Ecto.Repo.Schema.insert(
            __MODULE__,
            repo,
            value,
            Ecto.Repo.Supervisor.tuplet(repo, prepare_opts(:insert, opts))
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
            Ecto.Repo.Supervisor.tuplet(repo, prepare_opts(:insert, opts))
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
                     tenant_to_schema: 1,
                     all_tenants: 0,
                     tenant_migrations_path: 0,
                     default_prefix: 0,
                     override_migration_type: 1
    end
  end
end
