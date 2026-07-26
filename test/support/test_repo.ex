# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo do
  @moduledoc false
  use AshPostgres.Repo,
    otp_app: :ash_postgres

  # Selects the committed migration/snapshot set that matches the server
  # version.
  #
  # `use_builtin_uuidv7_function?/0` is derived from `min_pg_version/0`, which
  # here follows `PG_VERSION` — so on PostgreSQL 18 a `uuid_v7_primary_key`
  # renders its default as the server's builtin `uuidv7()` rather than Ash's
  # `uuid_generate_v7()`. Generated snapshots and migrations are therefore
  # genuinely version-specific, while CI runs
  # `mix ash_postgres.generate_migrations --check` on every version in the
  # matrix. Rather than one committed set that can only ever match a single
  # version, each variant gets its own; `mix test.generate_migrations`
  # regenerates all of them.
  def init(type, config) do
    {:ok, config} = super(type, config)

    if use_builtin_uuidv7_function?() do
      {:ok, AshPostgres.TestPaths.put_paths(config, "test_repo_pg18", "resource_snapshots_pg18")}
    else
      {:ok, AshPostgres.TestPaths.put_paths(config, "test_repo")}
    end
  end

  def on_transaction_begin(data) do
    send(self(), data)
  end

  def prefer_transaction?, do: false

  def prefer_transaction_for_atomic_updates?, do: false

  def installed_extensions do
    [
      "ash-functions",
      "uuid-ossp",
      "pg_trgm",
      "citext",
      AshPostgres.TestCustomExtension,
      AshPostgres.Extensions.ImmutableRaiseError,
      "ltree"
    ] --
      Application.get_env(:ash_postgres, :no_extensions, [])
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

  def all_tenants do
    Code.ensure_compiled(AshPostgres.MultitenancyTest.Org)

    AshPostgres.MultitenancyTest.Org
    |> Ash.read!()
    |> Enum.map(&"org_#{&1.id}")
  end

  def immutable_expr_error? do
    Application.get_env(:ash_postgres, :test_repo_use_immutable_errors?, false)
  end
end
