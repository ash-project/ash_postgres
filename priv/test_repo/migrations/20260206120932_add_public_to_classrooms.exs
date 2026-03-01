defmodule AshPostgres.TestRepo.Migrations.AddPublicToClassrooms do
  @moduledoc """
  Adds public column to classrooms for through relationship policy testing.
  """

  use Ecto.Migration

  def up do
    alter table(:classrooms) do
      add(:public, :boolean, default: true)
    end
  end

  def down do
    alter table(:classrooms) do
      remove(:public)
    end
  end
end
