# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.TenantPostLink do
  @moduledoc false
  # Links posts that aren't multitenant, scoped to an org by attribute.
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tenant_post_links"
    repo AshPostgres.TestRepo
  end

  multitenancy do
    strategy(:attribute)
    attribute(:org_id)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :destroy])
  end

  identities do
    identity(:unique_link, [:source_id, :dest_id])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:org_id, :uuid, allow_nil?: false)
  end

  relationships do
    belongs_to :source, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
    end

    belongs_to :dest, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
    end
  end
end
