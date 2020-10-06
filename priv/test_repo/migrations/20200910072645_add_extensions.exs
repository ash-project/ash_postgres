defmodule AshPostgres.TestRepo.Migrations.AddExtensions do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION \"uuid-ossp\";", "DROP EXTENSION \"uuid-ossp\"")
    execute("CREATE EXTENSION \"pg_trgm\";", "DROP EXTENSION \"pg_trgm\"")
  end
end
