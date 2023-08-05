defmodule AshPostgres.TestNoSandboxRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def on_transaction_begin(data) do
    send(self(), data)
  end

  def installed_extensions do
    ["ash-functions", "uuid-ossp", "pg_trgm", "citext", AshPostgres.TestCustomExtension.extension()] --
      Application.get_env(:ash_postgres, :no_extensions, [])
  end

  def all_tenants do
    Code.ensure_compiled(AshPostgres.MultitenancyTest.Org)

    AshPostgres.MultitenancyTest.Org
    |> AshPostgres.MultitenancyTest.Api.read!()
    |> Enum.map(&"org_#{&1.id}")
  end
end
