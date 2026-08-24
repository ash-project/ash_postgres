# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestPaths do
  @moduledoc false

  # The test repos' migrations and resource snapshots live in `test_priv/`
  # rather than the conventional `priv/`: they are scaffolding for this
  # library's own test suite, not files an `ash_postgres` user ever sees.
  #
  # They can't live under `test/` either. `.formatter.exs` formats
  # `test/**/*.exs`, and generated Ecto migrations use the unparenthesized
  # `add :column, :type` DSL, which this project's `locals_without_parens`
  # doesn't cover — `mix format` would rewrite every committed migration.
  #
  # Each repo routes itself here from its `init/2`, since only `repo.config()`
  # is consulted for these paths (see `AshPostgres.Mix.Helpers.migrations_path/2`
  # and `AshPostgres.MigrationGenerator`'s `snapshot_path/2`).
  @root "test_priv"

  @doc """
  Points a repo's migrations (`:priv`) and resource snapshots at `test_priv/`.

  `repo_dir` holds that one repo's `migrations/` and `tenant_migrations/`;
  `snapshots_dir` is the shared snapshot root, under which the generator
  creates a per-repo subdirectory.

  `:tenant_migrations_path` is set explicitly rather than left to derive from
  `:priv`. `AshPostgres.MultiTenancy.migrate_tenant/4` — the runtime path, used
  by `create_tenant!/2` — falls back to `:code.priv_dir(otp_app)` joined with
  the repo name, which is a compiled `_build` location that ignores `:priv`
  entirely, so nothing here would be found.
  """
  def put_paths(config, repo_dir, snapshots_dir \\ "resource_snapshots") do
    config
    |> Keyword.put(:priv, Path.join(@root, repo_dir))
    |> Keyword.put(:tenant_migrations_path, path([repo_dir, "tenant_migrations"]))
    |> Keyword.put(:snapshots_path, Path.join(@root, snapshots_dir))
  end

  @doc "A path within `test_priv/`, for tests that reach for one directly."
  def path(parts), do: Path.join([@root | List.wrap(parts)])
end
