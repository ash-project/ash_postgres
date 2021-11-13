defmodule AshPostgres.TestRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def installed_extensions do
    ["uuid-ossp", "pg_trgm", "citext"]
  end

  def all_tenants do
    Code.ensure_compiled(AshPostgres.MultitenancyTest.Org)

    AshPostgres.MultitenancyTest.Org
    |> AshPostgres.MultitenancyTest.Api.read!()
    |> Enum.map(&"org_#{&1.id}")
  end
end
