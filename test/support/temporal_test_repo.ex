# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TemporalTestRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  def init(type, config) do
    {:ok, config} = super(type, config)
    {:ok, AshPostgres.TestPaths.put_paths(config, "temporal_test_repo")}
  end

  def min_pg_version, do: %Version{major: 18, minor: 0, patch: 0}

  def installed_extensions, do: ["ash-functions", "citext", "btree_gist"]

  def prefer_transaction?, do: false

  def prefer_transaction_for_atomic_updates?, do: false

  def all_tenants, do: []
end
