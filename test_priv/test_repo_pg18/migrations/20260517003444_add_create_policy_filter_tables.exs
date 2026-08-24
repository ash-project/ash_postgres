# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddCreatePolicyFilterTables do
  @moduledoc """
  Tables for the post-insert filter-policy-on-create regression tests.

  These exercise Ash's `auto_filter`-on-create deferral path against a real
  transactional data layer, so we can verify rollback semantics actually
  rollback the row (something ETS can't demonstrate).
  """
  use Ecto.Migration

  def up do
    create table(:create_policy_filter_orgs, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :owner_id, :uuid, null: false
    end

    create table(:create_policy_filter_posts, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :text, :text, null: false

      add :organization_id,
          references(:create_policy_filter_orgs,
            column: :id,
            type: :uuid,
            on_delete: :delete_all
          )
    end
  end

  def down do
    drop table(:create_policy_filter_posts)
    drop table(:create_policy_filter_orgs)
  end
end
