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

  def mix_tasks do
    [
      {"Postgres",
       [
         Mix.Tasks.AshPostgres.GenerateMigrations,
         Mix.Tasks.AshPostgres.Create,
         Mix.Tasks.AshPostgres.Drop,
         Mix.Tasks.AshPostgres.Migrate,
         Mix.Tasks.AshPostgres.Rollback
       ]}
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
         AshPostgres.Functions.TrigramSimilarity
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
