defmodule AshPostgres.TestRepo.TenantMigrations.MigrateResources6 do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    drop(constraint("composite_key", "composite_key_pkey", prefix: prefix()))

    alter table(:composite_key, prefix: prefix()) do
      modify(:title, :text)
    end

    execute("ALTER TABLE \"#{prefix()}\".\"composite_key\" ADD PRIMARY KEY (id, title)")
  end

  def down do
    drop(constraint("composite_key", "composite_key_pkey", prefix: prefix()))

    alter table(:composite_key, prefix: prefix()) do
      modify(:title, :text)
    end

    execute("ALTER TABLE \"#{prefix()}\".\"composite_key\" ADD PRIMARY KEY (id)")
  end
end
