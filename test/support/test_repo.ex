defmodule AshPostgres.TestRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def on_transaction_begin(data) do
    send(self(), data)
  end

  def installed_extensions do
    ["ash-functions", "uuid-ossp", "pg_trgm", "citext", AshPostgres.TestCustomExtension] --
      Application.get_env(:ash_postgres, :no_extensions, [])
  end

  def min_pg_version do
    case System.get_env("PG_VERSION") do
      nil -> %Version{major: 16, minor: 0, patch: 0}
      version -> Version.parse!(version)
    end
  end

  def all_tenants do
    Code.ensure_compiled(AshPostgres.MultitenancyTest.Org)

    AshPostgres.MultitenancyTest.Org
    |> Ash.read!()
    |> Enum.map(&"org_#{&1.id}")
  end
end
