defmodule AshPostgres.TestRepo.Migrations.UserInvites do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    alter table(:users) do
      add(:role, :text, default: "user")
    end

    create table(:user_invites, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:name, :text, null: false)
      add(:role, :text, null: false)
    end
  end

  def down do
    drop(table(:user_invites))

    alter table(:users) do
      remove(:role)
    end
  end
end
