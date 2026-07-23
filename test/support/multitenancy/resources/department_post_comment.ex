# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.DepartmentPostComment do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:text, :string, public?: true)
    attribute(:organization_id, :uuid, public?: true)
    attribute(:department_id, :uuid, public?: true)
  end

  postgres do
    table "department_post_comments"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  multitenancy do
    strategy(:attribute)
    attribute(:department_id)
    ancestor_attributes([:organization_id])
  end

  relationships do
    belongs_to :post, AshPostgres.MultitenancyTest.DepartmentPost do
      public?(true)
    end
  end
end
