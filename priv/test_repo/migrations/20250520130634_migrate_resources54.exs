defmodule AshPostgres.TestRepo.Migrations.MigrateResources54 do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    alter table(:posts) do
      add(:person_detail, :map)
    end
  end

  def down do
    alter table(:posts) do
      remove(:person_detail)
    end
  end
end
