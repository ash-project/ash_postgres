# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Verifiers.VerifyTemporal do
  @moduledoc false
  # A temporal resource needs:
  #
  # - PostgreSQL 18+, for `WITHOUT OVERLAPS` primary keys, `PERIOD` foreign keys and
  #   `RETURNING old`. Migrations emit that DDL unconditionally, so the repo has to
  #   declare it with `min_pg_version/0`.
  # - The `btree_gist` extension, since the `WITHOUT OVERLAPS` primary key is backed by
  #   a GiST exclusion constraint. The repo has to declare it in `installed_extensions/0`
  #   so migrations install it.
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    repo = AshPostgres.DataLayer.Info.repo(dsl, :mutate)

    if is_nil(Ash.Resource.Info.temporal_strategy(dsl)) or is_nil(repo) or
         not Code.ensure_loaded?(repo) do
      :ok
    else
      resource = Verifier.get_persisted(dsl, :module)

      with :ok <- verify_min_pg_version(resource, repo) do
        verify_btree_gist(resource, repo)
      end
    end
  end

  defp verify_min_pg_version(resource, repo) do
    with true <- function_exported?(repo, :min_pg_version, 0),
         %Version{major: major} = version when major < 18 <- repo.min_pg_version() do
      raise Spark.Error.DslError,
        module: resource,
        message: """
        Temporal resource #{inspect(resource)} requires PostgreSQL 18 or later.

        `#{inspect(repo)}.min_pg_version/0` is #{version}. Temporal resources rely on
        `WITHOUT OVERLAPS` primary keys, `PERIOD` foreign keys and `RETURNING old`,
        which arrived in PostgreSQL 18. If your database is on 18 or later, say so:

        ```elixir
        def min_pg_version do
          %Version{major: 18, minor: 0, patch: 0}
        end
        ```
        """,
        path: [:temporal]
    else
      _ -> :ok
    end
  end

  defp verify_btree_gist(resource, repo) do
    with true <- function_exported?(repo, :installed_extensions, 0),
         false <- "btree_gist" in repo.installed_extensions() do
      raise Spark.Error.DslError,
        module: resource,
        message: """
        Temporal resource #{inspect(resource)} requires the `btree_gist` extension.

        Its `WITHOUT OVERLAPS` primary key is backed by a GiST exclusion constraint,
        which needs `btree_gist`. Add it to your repo's `installed_extensions/0`:

        ```elixir
        def installed_extensions do
          ["btree_gist"]
        end
        ```
        """,
        path: [:temporal]
    else
      _ -> :ok
    end
  end
end
