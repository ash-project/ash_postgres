# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.CrossTenantPostLink do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "cross_tenant_post_links"
    repo AshPostgres.TestRepo
  end

  multitenancy do
    strategy(:context)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  relationships do
    belongs_to(:source, AshPostgres.Test.Post,
      primary_key?: true,
      allow_nil?: false
    )

    belongs_to(:dest, AshPostgres.MultitenancyTest.Post,
      primary_key?: true,
      allow_nil?: false
    )
  end
end
