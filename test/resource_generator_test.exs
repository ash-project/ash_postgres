defmodule AshPostgres.RelWithParentFilterTest do
  use AshPostgres.RepoCase, async: false

  setup do
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS example_table")
    AshPostgres.TestRepo.query!("CREATE TABLE example_table (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      name VARCHAR(255),
      age INTEGER,
      email VARCHAR(255)
    )")

    on_exit(fn ->
      AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS example_table")
    end)
  end

  test "a resource is generated from a table" do
    Igniter.new()
    |> Igniter.compose_task("ash_postgres.gen.resources", [
      "MyApp.Accounts",
      "--tables",
      "example_table",
      "--yes"
    ])
  end
end
