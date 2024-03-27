defmodule AshPostgres.MultitenancyTest.Org do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

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

  relationships do
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
end
