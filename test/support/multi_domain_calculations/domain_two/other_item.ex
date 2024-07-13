defmodule AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    domain: AshPostgres.Test.MultiDomainCalculations.DomainTwo

  alias AshPostgres.Test.MultiDomainCalculations.DomainOne.Item
  alias AshPostgres.Test.MultiDomainCalculations.DomainTwo.SubItem

  attributes do
    uuid_v7_primary_key(:id)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:item, Item, allow_nil?: false)
    has_many(:sub_items, SubItem)
  end

  actions do
    defaults([:read, :destroy, create: [:*, :item_id], update: :*])
  end

  aggregates do
    sum :total_sub_items_amount, :sub_items, :total_amount do
      default(0)
    end
  end

  calculations do
    calculate(:total_amount, :integer, expr(total_sub_items_amount))
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  postgres do
    table "other_items"
    repo(AshPostgres.TestRepo)

    references do
      reference :item, on_delete: :delete, index?: true
    end
  end
end
