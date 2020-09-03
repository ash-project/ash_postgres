defmodule AshPostgres.TestRepo.Migrations.AddPosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add(:title, :string)
      add(:score, :integer)
      add(:public, :boolean)
    end
  end
end
