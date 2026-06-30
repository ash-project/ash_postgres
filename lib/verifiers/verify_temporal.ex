# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Verifiers.VerifyTemporal do
  @moduledoc false
  # A temporal resource's `WITHOUT OVERLAPS` primary key is backed by a GiST
  # exclusion constraint, which requires the `btree_gist` extension. Ensure the
  # repo declares it in `installed_extensions/0` so migrations install it.
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    if is_nil(Ash.Resource.Info.temporal_strategy(dsl)) do
      :ok
    else
      repo = AshPostgres.DataLayer.Info.repo(dsl, :mutate)

      with true <- not is_nil(repo) and Code.ensure_loaded?(repo),
           true <- function_exported?(repo, :installed_extensions, 0),
           false <- "btree_gist" in repo.installed_extensions() do
        resource = Verifier.get_persisted(dsl, :module)

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
end
