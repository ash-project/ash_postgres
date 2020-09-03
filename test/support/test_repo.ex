defmodule AshPostgres.TestRepo do
  use AshPostgres.Repo,
    otp_app: :ash_postgres
end
