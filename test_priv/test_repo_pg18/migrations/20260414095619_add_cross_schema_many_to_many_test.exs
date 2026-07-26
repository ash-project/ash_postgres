# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddCrossSchemaM2MTest do
  @moduledoc """
  Migration for cross-schema many_to_many regression test.

  Creates:
  - "interest" schema
  - interests table in "interest" schema
  - profile_interests table in "profiles" schema (join table)

  This tests true cross-schema many_to_many between two custom schemas:
  - Interest in "interest" schema
  - Profile in "profiles" schema
  - ProfileInterest join table in "profiles" schema
  """
  use Ecto.Migration

  def up do
    # Create the "interest" schema
    execute "CREATE SCHEMA IF NOT EXISTS interest"

    # Interest table in "interest" schema
    create table(:interests, primary_key: false, prefix: "interest") do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text
    end

    # ProfileInterest join table in "profiles" schema
    create table(:profile_interests, primary_key: false, prefix: "profiles") do
      add :id, :uuid, null: false, primary_key: true

      add :profile_id,
          references(:profile,
            column: :id,
            name: "profile_interests_profile_id_fkey",
            type: :uuid,
            prefix: "profiles"
          ),
          null: false

      add :interest_id,
          references(:interests,
            column: :id,
            name: "profile_interests_interest_id_fkey",
            type: :uuid,
            prefix: "interest"
          ),
          null: false
    end

    create unique_index(:profile_interests, [:profile_id, :interest_id], prefix: "profiles")
  end

  def down do
    drop table(:profile_interests, prefix: "profiles")
    drop table(:interests, prefix: "interest")
    execute "DROP SCHEMA IF EXISTS interest"
  end
end
