# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.MultiDomainCalculations.DomainTwo.SubItem do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    domain: AshPostgres.Test.MultiDomainCalculations.DomainTwo

  alias AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:amount, :integer, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:other_item, OtherItem, allow_nil?: false)
  end

  actions do
    defaults([:read, :destroy, create: [:*, :other_item_id, :amount], update: :*])
  end

  calculations do
    calculate(:total_amount, :integer, expr(amount))

    calculate(
      :total_amount_relationship,
      :integer,
      expr(amount * other_item.item.relationship_item.value)
    )
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  postgres do
    table "sub_items"
    repo(AshPostgres.TestRepo)

    references do
      reference :other_item, on_delete: :delete, index?: true
    end
  end
end
