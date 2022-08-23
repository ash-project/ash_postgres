defmodule AshPostgres.DocIndex do
  @moduledoc """
  Some documentation about AshPostgres.
  """
  use Spark.DocIndex,
    guides_from: [
      "documentation/**/*.md"
    ]

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

  def code_modules, do: []
end
