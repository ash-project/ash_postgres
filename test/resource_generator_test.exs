defmodule AshPostgres.ResourceGeenratorTests do
  use AshPostgres.RepoCase, async: false

  setup do
    AshPostgres.TestRepo.query!("DROP TABLE IF EXISTS example_table")

    AshPostgres.TestRepo.query!("CREATE TABLE example_table (
      id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
      name VARCHAR(255),
      age INTEGER,
      email VARCHAR(255)
    )")

    :ok
  end

  test "a resource is generated from a table" do
    resource =
      Igniter.new()
      |> Igniter.compose_task("ash_postgres.gen.resources", [
        "MyApp.Accounts",
        "--tables",
        "example_table",
        "--yes"
      ])
      |> Igniter.prepare_for_write()
      |> Map.get(:rewrite)
      |> Rewrite.source!("lib/my_app/accounts/example_table.ex")
      |> Rewrite.Source.get(:content)

    assert String.trim(resource) ==
             String.trim("""
             defmodule MyApp.Accounts.ExampleTable do
               use Ash.Resource,
                 domain: MyApp.Accounts,
                 data_layer: AshPostgres.DataLayer

               postgres do
                 table "example_table"
                 repo AshPostgres.TestRepo
               end

               attributes do
                 uuid_primary_key(:id)
                 attribute(:name, :string)
                 attribute(:age, :integer)

                 attribute :email, :string do
                   sensitive?(true)
                 end
               end
             end
             """)
  end
end
