# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RepoNoSandboxCase do
  @moduledoc """
  Test case for testing database operations without sandbox transaction wrapping.

  This is useful for testing operations that cannot run inside transactions,
  such as concurrent index creation with @disable_ddl_transaction.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias AshPostgres.TestRepo

      import Ecto
      import Ecto.Query
      import AshPostgres.RepoNoSandboxCase

      # and any other stuff
    end
  end

  setup _tags do
    # No sandbox setup - just ensure the repo is available
    # This allows testing operations that cannot run in transactions
    :ok
  end
end
