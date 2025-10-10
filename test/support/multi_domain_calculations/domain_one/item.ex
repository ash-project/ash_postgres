# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.MultiDomainCalculations.DomainOne.Item do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    domain: AshPostgres.Test.MultiDomainCalculations.DomainOne

  alias AshPostgres.Test.MultiDomainCalculations.DomainThree.RelationshipItem
  alias AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:key, :string)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_one(:other_item, OtherItem)

    has_one(:relationship_item, RelationshipItem) do
      no_attributes?(true)
      filter(expr(parent(key) == key))
    end
  end

  actions do
    defaults([:read, :destroy, update: :*, create: [:*, :key]])
  end

  calculations do
    calculate(:total_amount, :integer, expr(other_item.total_amount))
    calculate(:total_amount_relationship, :integer, expr(other_item.total_amount_relationship))
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  postgres do
    table "items"
    repo(AshPostgres.TestRepo)
  end
end
