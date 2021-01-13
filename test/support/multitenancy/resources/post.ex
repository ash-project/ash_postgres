defmodule AshPostgres.MultitenancyTest.Post do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string)
  end

  actions do
    create(:create)
    read(:read)
    update(:update)
    destroy(:destroy)
  end

  postgres do
    table "multitenant_posts"
    repo AshPostgres.TestRepo
  end

  multitenancy do
    # Tells the resource to use the data layer
    # multitenancy, in this case separate postgres schemas
    strategy(:context)
  end

  relationships do
    belongs_to(:org, AshPostgres.MultitenancyTest.Org)
  end
end
