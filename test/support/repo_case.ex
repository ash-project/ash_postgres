# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RepoCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias AshPostgres.TestRepo

      import Ecto
      import Ecto.Query
      import AshPostgres.RepoCase

      # and any other stuff
    end
  end

  setup tags do
    # `AshPostgres.TemporalTestRepo` is only started on PostgreSQL 18+.
    repos =
      [AshPostgres.TestRepo, AshPostgres.TemporalTestRepo]
      |> Enum.filter(&Process.whereis/1)

    for repo <- repos do
      :ok = Sandbox.checkout(repo)

      if !tags[:async] do
        Sandbox.mode(repo, {:shared, self()})
      end
    end

    :ok
  end
end
