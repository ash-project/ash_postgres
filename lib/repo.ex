defmodule AshPostgres.Repo do
  @moduledoc """
  Resources that use `AshPostgres.DataLayer` use a `Repo` to access the database.

  This repo is a thin wrapper around an `Ecto.Repo`.

  You can use `Ecto.Repo`'s `init/2` to configure your repo like normal, but
  instead of returning `{:ok, config}`, use `super(config)` to pass the
  configuration to the `AshPostgres.Repo` implementation.

  ## Installed Extensions

  To configure your list of installed extensions, define `installed_extensions/0`

  All extensions present will be automatically added by the migration generator. Some extensions
  being present in the list can change how AshPostgres behaves.

  Extensions that are relevant to ash_postgres:

  * "ash-functions" - This isn't really an extension, but it expresses that certain functions
    should be added when generating migrations, to support the `||` and `&&` operators in expressions.
  * `"pg_trgm"` - Makes the `AshPostgres.Predicates.Trigram` custom predicate available
  * "citext" - Allows case insensitive fields to be used

  ```
  def installed_extensions() do
    ["pg_trgm", "uuid-ossp"]
  end
  ```
  """

  @doc "Use this to inform the data layer about what extensions are installed"
  @callback installed_extensions() :: [String.t()]

  @doc """
  Use this to inform the data layer about the oldest potential postgres version it will be run on.

  Must be an integer greater than or equal to 13.
  """
  @callback min_pg_version() :: integer()

  @doc "Return a list of all schema names (only relevant for a multitenant implementation)"
  @callback all_tenants() :: [String.t()]
  @doc "The path where your tenant migrations are stored (only relevant for a multitenant implementation)"
  @callback tenant_migrations_path() :: String.t()
  @doc "The path where your migrations are stored"
  @callback migrations_path() :: String.t()
  @doc "The default prefix(postgres schema) to use when building queries"
  @callback default_prefix() :: String.t()
  @doc "Allows overriding a given migration type for *all* fields, for example if you wanted to always use :timestamptz for :utc_datetime fields"
  @callback override_migration_type(atom) :: atom

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      otp_app = opts[:otp_app] || raise("Must configure OTP app")

      use Ecto.Repo,
        adapter: Ecto.Adapters.Postgres,
        otp_app: otp_app

      def installed_extensions, do: []
      def tenant_migrations_path, do: nil
      def migrations_path, do: nil
      def default_prefix, do: "public"
      def override_migration_type(type), do: type
      def min_pg_version(), do: 10

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

      defoverridable init: 2,
                     installed_extensions: 0,
                     all_tenants: 0,
                     tenant_migrations_path: 0,
                     default_prefix: 0,
                     override_migration_type: 1,
                     min_pg_version: 0
    end
  end
end
