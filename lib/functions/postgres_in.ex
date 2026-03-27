# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Functions.PostgresIn do
  @moduledoc """
  Generates a native SQL `IN (...)` clause instead of the default `= ANY(...)` array syntax.

  PostgreSQL's query planner may choose different (sometimes suboptimal) indexes when using
  `= ANY('{...}'::type[])` compared to `IN ($1, $2, ...)`. This function provides an escape
  hatch for cases where the native `IN` syntax produces better query plans.

  ## Example

      filter(query, postgres_in(id, [^id1, ^id2, ^id3]))

  Generates:

      WHERE id IN ($1, $2, $3)

  Instead of the default:

      WHERE id = ANY($1::uuid[])

  See: https://github.com/ash-project/ash/issues/2605
  """

  use Ash.Query.Function, name: :postgres_in, predicate?: true

  def args, do: [[:any, {:array, :any}]]
end
