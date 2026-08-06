# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.DepartmentPost do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
    attribute(:organization_id, :uuid, public?: true)
    attribute(:department_id, :uuid, public?: true)
  end

  postgres do
    table "department_posts"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

    create :upsert_by_name do
      upsert?(true)
      upsert_identity(:unique_name)
      upsert_fields([:name])
    end
  end

  identities do
    identity(:unique_name, [:name])
  end

  multitenancy do
    strategy(:attribute)
    attribute(:department_id)
    ancestor_attributes([:organization_id])
  end

  relationships do
    has_many :comments, AshPostgres.MultitenancyTest.DepartmentPostComment do
      destination_attribute(:post_id)
      public?(true)
    end
  end

  aggregates do
    count(:count_of_comments, :comments)
  end
end
