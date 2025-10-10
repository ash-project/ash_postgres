# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.MultiDomainCalculations.DomainThree.RelationshipItem do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    domain: AshPostgres.Test.MultiDomainCalculations.DomainThree

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:key, :string, allow_nil?: false)
    attribute(:value, :integer, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read, :destroy, update: :*, create: [:*, :key, :value]])
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  postgres do
    table "relationship_items"
    repo(AshPostgres.TestRepo)
  end
end
