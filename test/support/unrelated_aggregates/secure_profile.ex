defmodule AshPostgres.Test.UnrelatedAggregatesTest.SecureProfile do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("unrelated_secure_profiles")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
    attribute(:age, :integer, public?: true)
    attribute(:active, :boolean, default: true, public?: true)
    attribute(:owner_id, :uuid, public?: true)
    attribute(:department, :string, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  policies do
    # Allow creation/updates for testing setup
    policy action_type([:create, :update, :destroy]) do
      authorize_if(always())
    end

    # Only allow users to see their own profiles, or admins to see all
    policy action_type(:read) do
      authorize_if(actor_attribute_equals(:role, :admin))
      authorize_if(expr(owner_id == ^actor(:id)))
    end
  end
end
