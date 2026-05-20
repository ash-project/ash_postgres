# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.TenantScopedUpsertTest do
  @moduledoc """
  Regression test for https://github.com/ash-project/ash_postgres/issues/755.

  When a resource uses `:attribute` multitenancy and declares an identity with
  `all_tenants?: false`, the upsert `ON CONFLICT` clause must include the
  multitenancy attribute in the conflict target. The unique index in postgres
  is created on `(tenant_attribute, ...identity_keys)`, so omitting the
  tenant attribute produces an `ON CONFLICT` clause that does not match any
  unique constraint.

  Previously the tenant attribute was only included when the changeset had a
  tenant set (or the identity used `nils_distinct?: false`), which broke
  upserts on resources marked `global?: true` where the tenant attribute is
  supplied as a regular accepted attribute rather than via `set_tenant/2`.
  """

  use AshPostgres.RepoCase, async: false
  require Ash.Query

  defmodule Domain do
    use Ash.Domain

    resources do
      allow_unregistered?(true)
    end
  end

  defmodule Record do
    use Ash.Resource,
      domain: Domain,
      data_layer: AshPostgres.DataLayer

    postgres do
      table("tenant_scoped_upsert_records")
      repo(AshPostgres.TestRepo)
    end

    attributes do
      uuid_primary_key(:id, writable?: true)
      attribute(:org_id, :uuid, public?: true, allow_nil?: false)
      attribute(:name, :string, public?: true, allow_nil?: false)
      attribute(:status, :string, public?: true)
    end

    identities do
      identity(:unique_name_per_org, [:name])
    end

    multitenancy do
      strategy(:attribute)
      attribute(:org_id)
      global?(true)
    end

    actions do
      default_accept(:*)
      defaults([:read, :destroy, create: :*, update: :*])

      create :import do
        accept([:org_id, :name])
        change(set_attribute(:status, "activated"))
        upsert?(true)
        upsert_identity(:unique_name_per_org)
        upsert_fields([:status])
      end
    end
  end

  test "upsert respects all_tenants?: false on the identity without a tenant set" do
    org1 = Ash.UUID.generate()
    org2 = Ash.UUID.generate()

    %{id: id1, status: "activated"} =
      Record
      |> Ash.Changeset.for_create(:import, %{org_id: org1, name: "alice"})
      |> Ash.create!()

    # Same name, different org — the unique index is on (org_id, name) so this
    # must NOT conflict and must insert a brand new row.
    %{id: id2, status: "activated"} =
      Record
      |> Ash.Changeset.for_create(:import, %{org_id: org2, name: "alice"})
      |> Ash.create!()

    refute id1 == id2

    # Same name AND same org — this one MUST conflict and update the existing row.
    %{id: ^id1, status: "activated"} =
      Record
      |> Ash.Changeset.for_create(:import, %{org_id: org1, name: "alice"})
      |> Ash.create!()
  end
end
