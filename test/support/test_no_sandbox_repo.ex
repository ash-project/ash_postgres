defmodule AshPostgres.TestNoSandboxRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def on_transaction_begin(data) do
    send(self(), data)
  end

  def pg_version do
    version =
      case System.get_env("PG_VERSION") do
        nil -> "16.0.0"
        "14" -> "14.0.0"
        "15" -> "15.0.0"
        "16" -> "16.0.0"
      end

    Version.parse!(version)
  end

  def installed_extensions do
    ["ash-functions", "uuid-ossp", "pg_trgm", "citext", AshPostgres.TestCustomExtension] --
      Application.get_env(:ash_postgres, :no_extensions, [])
  end

  def all_tenants do
    Code.ensure_compiled(AshPostgres.MultitenancyTest.Org)

    AshPostgres.MultitenancyTest.Org
    |> Ash.read!()
    |> Enum.map(&"org_#{&1.id}")
  end
end
