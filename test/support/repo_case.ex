defmodule AshPostgres.RepoCase do
  use ExUnit.CaseTemplate

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
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AshPostgres.TestRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(AshPostgres.TestRepo, {:shared, self()})
    end

    :ok
  end
end
