# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TemporalTestRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  # Temporal resources need PostgreSQL 18+ (see `AshPostgres.Verifiers.VerifyTemporal`),
  # while the rest of the suite also runs on older servers. So they get a repo of their
  # own, in the same database, that's only migrated and started when testing against 18+
  # (see `config/config.exs` and `test/test_helper.exs`). On older servers the resources
  # still compile, and their tests are excluded by the `:postgres_18` tag.
  #
  # See `AshPostgres.TestPaths` for why the migrations live outside `priv/`.
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
