# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationGenerator.OperationCycleError do
  @moduledoc """
  Raised when the migration operation dependency graph contains a cycle,
  i.e. two or more operations require facts that only each other provide.
  """
  defexception [:operations]

  @impl true
  def message(%{operations: operations}) do
    described =
      operations
      |> Enum.map(&describe_operation/1)
      |> Enum.map(&"  - #{&1}")
      |> Enum.join("\n")

    """
    Could not determine a valid order for the following migration operations \
    because they form a dependency cycle:

    #{described}

    If two tables have foreign keys pointing at each other, split the \
    change into multiple migrations (e.g. create both tables first, add \
    the foreign keys afterward) or make one of them nullable/deferrable.

    Otherwise, this is most likely a bug in AshPostgres's migration \
    ordering logic rather than something you can fix in your resources \
    — please open an issue at \
    https://github.com/ash-project/ash_postgres/issues with the \
    resources involved.
    """
  end

  defp describe_operation(op) do
    table = Map.get(op, :table)
    schema = Map.get(op, :schema)

    "#{inspect(op.__struct__)} on #{inspect(table)}#{if schema, do: " (schema: #{inspect(schema)})", else: ""}"
  end
end
