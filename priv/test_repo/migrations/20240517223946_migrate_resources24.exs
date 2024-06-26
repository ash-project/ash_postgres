defmodule AshPostgres.TestRepo.Migrations.MigrateResources24 do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    alter table(:post_followers) do
      add(:order, :bigint)
    end
  end

  def down do
    alter table(:post_followers) do
      remove(:order)
    end
  end
end
