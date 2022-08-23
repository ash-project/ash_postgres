defmodule AshPostgres.DocIndex do
  @moduledoc false
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

  def code_modules do
    [
      {"AshPostgres",
       [
         AshPostgres.Repo
       ]},
      {"Postgres Expressions",
       [
         AshPostgres.Functions.Fragment,
         AshPostgres.Functions.TrigramSimilarity,
         AshPostgres.Functions.Type
       ]},
      {"Postgres Migrations",
       [
         AshPostgres.Migration,
         EctoMigrationDefault
       ]},
      {"Introspection",
       [
         AshPostgres.DataLayer.Info
       ]}
    ]
  end
end
