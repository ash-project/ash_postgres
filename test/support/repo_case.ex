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
    :ok = Sandbox.checkout(AshPostgres.TestRepo)

    unless tags[:async] do
      Sandbox.mode(AshPostgres.TestRepo, {:shared, self()})
    end

    :ok
  end
end
