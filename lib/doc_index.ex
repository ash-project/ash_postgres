defmodule AshPostgres.DocIndex do
  @moduledoc """
  Some documentation about AshPostgres.
  """
  @behaviour Ash.DocIndex

  def for_library, do: "ash_postgres"

  def extensions do
    [
      %{
        module: AshPostgres.DataLayer,
        name: "AshPostgres",
        target: "Ash.Resource",
        type: "DataLayer"
      }
    ]
  end
end
