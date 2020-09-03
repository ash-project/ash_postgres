defmodule AshPostgres.TestRepo.Migrations.AddComments do
  use Ecto.Migration

  def change do
    create table(:comments) do
      add(:title, :string)
      add(:post_id, references(:posts))
    end
  end
end
