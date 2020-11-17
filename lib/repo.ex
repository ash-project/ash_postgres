defmodule AshPostgres.Repo do
  @moduledoc """
  Resources that use the `AshPostgres` data layer use a `Repo` to access the database.

  This repo is a slightly modified version of an `Ecto.Repo`.

  You can use `Ecto.Repo`'s `init/2` to configure your repo like normal, but
  instead of returning `{:ok, config}`, use `super(config)` to pass the
  configuration to the `AshPostgres.Repo` implementation.

  ## Installed Extensions

  To configure your list of installed extensions, define `installed_extensions/0`

  Extensions that are relevant to ash_postgres:

  * `"uuid-ossp"` - Sets UUID primary keys defaults in the migration generator
  * `"pg_trgm"` - Makes the `AshPostgres.Predicates.Trigram` custom predicate available

  ```
  def installed_extensions() do
    ["pg_trgm", "uuid-ossp"]
  end
  ```
  """

  @doc "Use this to inform the data layer about what extensions are installed"
  @callback installed_extensions() :: [String.t()]
  @doc "Return a list of all schema names (only relevant for a multitenant implementation)"
  @callback all_tenants() :: [String.t()]
  @doc "The path where your tenant migrations are stored (only relevant for a multitenant implementation)"
  @callback tenant_migrations_path() :: String.t()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      otp_app = opts[:otp_app] || raise("Must configure OTP app")

      use Ecto.Repo,
        adapter: Ecto.Adapters.Postgres,
        otp_app: otp_app

      def installed_extensions, do: []
      def tenant_migrations_path, do: nil
      def all_tenants, do: []

      def init(_, config) do
        new_config =
          config
          |> Keyword.put(:installed_extensions, installed_extensions())
          |> Keyword.put(:tenant_migrations_path, tenant_migrations_path())

        {:ok, new_config}
      end

      defoverridable installed_extensions: 0, all_tenants: 0, tenant_migrations_path: 0
    end
  end
end
