defmodule AshPostgres.Test.MultiDomainCalculations.DomainOne.Item do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    domain: AshPostgres.Test.MultiDomainCalculations.DomainOne

  alias AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem

  attributes do
    uuid_v7_primary_key(:id)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_one(:other_item, OtherItem)
  end

  actions do
    defaults([:read, :destroy, update: :*, create: :*])
  end

  calculations do
    calculate(:total_amount, :integer, expr(other_item.total_amount))
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
