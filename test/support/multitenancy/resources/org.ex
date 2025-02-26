defmodule AshPostgres.MultitenancyTest.Org do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  defimpl Ash.ToTenant do
    def to_tenant(%{id: id}, resource) do
      if Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer &&
           Ash.Resource.Info.multitenancy_strategy(resource) == :context do
        "org_#{id}"
      else
        id
      end
    end
  end

  policies do
    policy action(:has_policies) do
      authorize_if(relates_to_actor_via(:owner))
    end

    # policy always() do
    #   authorize_if(always())
    # end
  end

  identities do
    identity(:unique_by_name, [:name])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

    read(:has_policies)
  end

  postgres do
    table "multitenant_orgs"
    repo(AshPostgres.TestRepo)

    manage_tenant do
      template(["org_", :id])
    end
  end

  multitenancy do
    strategy(:attribute)
    attribute(:id)
    global?(true)
    parse_attribute({__MODULE__, :tenant, []})
  end

  aggregates do
    count(:total_users_posts, [:users, :posts])
    count(:total_posts, :posts)
  end

  relationships do
    belongs_to :owner, AshPostgres.MultitenancyTest.User do
      attribute_public?(false)
      public?(false)
    end

    has_many(:posts, AshPostgres.MultitenancyTest.Post,
      destination_attribute: :org_id,
      public?: true
    )

    has_many(:users, AshPostgres.MultitenancyTest.User,
      destination_attribute: :org_id,
      public?: true
    )
  end

  def tenant("org_" <> tenant) do
    tenant
  end

  def tenant(tenant) do
    tenant
  end
end
