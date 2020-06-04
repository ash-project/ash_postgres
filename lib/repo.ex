defmodule AshPostgres.Repo do
  @moduledoc """
  Resources that use the `AshPostgres` data layer use a `Repo` to access the database.

  This module is where database connection and configuration options go.
  """
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

      def init(:supervisor, config) do
        new_config = Keyword.put(config, :installed_extensions, installed_extensions())

        {:ok, new_config}
      end

      def init(:runtime, config) do
        init(:supervisor, config)
      end

      defoverridable installed_extensions: 0
    end
  end
end
