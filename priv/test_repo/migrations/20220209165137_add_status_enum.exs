defmodule AshPostgres.TestRepo.Migrations.AddStatusEnum do
  use Ecto.Migration

  def change do
    execute("""
    CREATE TYPE status AS ENUM ('open', 'closed');
    """, """
    DROP TYPE status;
    """
    )
  end
end
