defmodule AshPostgres.TestRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def installed_extensions do
    ["uuid-ossp"]
  end
end
