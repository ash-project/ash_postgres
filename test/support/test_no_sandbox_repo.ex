# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestNoSandboxRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def on_transaction_begin(data) do
    send(self(), data)
  end

  def min_pg_version do
    case System.get_env("PG_VERSION") do
      nil ->
        %Version{major: 16, minor: 0, patch: 0}

      version ->
        case Integer.parse(version) do
          {major, ""} -> %Version{major: major, minor: 0, patch: 0}
          _ -> Version.parse!(version)
        end
    end
  end

  def installed_extensions do
    ["ash-functions", "uuid-ossp", "pg_trgm", "citext", AshPostgres.TestCustomExtension] --
      Application.get_env(:ash_postgres, :no_extensions, [])
  end

  def all_tenants do
    []
  end
end
