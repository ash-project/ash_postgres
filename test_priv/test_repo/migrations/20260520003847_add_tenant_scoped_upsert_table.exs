# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddTenantScopedUpsertTable do
  @moduledoc """
  Table for the tenant-scoped upsert regression test (issue #755).

  Exercises a multitenancy `:attribute` resource with an identity that
  has `all_tenants?: false` so we can verify the `ON CONFLICT` clause
  on upsert includes the tenant attribute even when no tenant is set
  on the changeset.
  """
  use Ecto.Migration

  def up do
    create table(:tenant_scoped_upsert_records, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :org_id, :uuid, null: false
      add :name, :text, null: false
      add :status, :text
    end

    create unique_index(:tenant_scoped_upsert_records, [:org_id, :name],
             name: "tenant_scoped_upsert_records_org_id_name_index"
           )
  end

  def down do
    drop table(:tenant_scoped_upsert_records)
  end
end
