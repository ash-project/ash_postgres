defmodule AshPostgres.MultitenancyTest.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy always() do
      authorize_if(always())
    end

    policy action(:update_with_policy) do
      # this is silly, but we want to force it to make a query
      authorize_if(expr(exists(self, true)))
    end
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string)
  end

  actions do
    default_accept :*

    defaults([:create, :read, :update, :destroy])

    update(:update_with_policy)
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
    belongs_to(:user, AshPostgres.MultitenancyTest.User)
    has_one(:self, __MODULE__, destination_attribute: :id, source_attribute: :id)
  end
end
