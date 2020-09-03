defmodule AshPostgres.Repo do
  @moduledoc """
  Resources that use the `AshPostgres` data layer use a `Repo` to access the database.

  This repo is a slightly modified version of an `Ecto.Repo`.

  You can use `Ecto.Repo`'s `init/2` to configure your repo like normal, but
  instead of returning `{:ok, config}`, use `super(config)` to pass the
  configuration to the `AshPostgres.Repo` implementation.

  Currently the only additional configuration supported is `installed_extensions`,
  and the only extension that ash_postgres reacts to is `"pg_trgm"`. If this extension
  is installed, then the `AshPostgres.Predicates.Trigram` custom predicate will be
  available.


  ```
  def installed_extensions() do
    ["pg_trgm"]
  end
  ```
  """

  @doc "Use this to inform the data layer about what extensions are installed"
  @callback installed_extensions() :: [String.t()]

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      otp_app = opts[:otp_app] || raise("Must configure OTP app")

      use Ecto.Repo,
        adapter: Ecto.Adapters.Postgres,
        otp_app: otp_app

      def installed_extensions do
        []
      end

      def init(_, config) do
        new_config = Keyword.put(config, :installed_extensions, installed_extensions())

        {:ok, new_config}
      end

      defoverridable installed_extensions: 0
    end
  end
end
