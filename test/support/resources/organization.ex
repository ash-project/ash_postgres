defmodule AshPostgres.Test.Organization do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  postgres do
    table("orgs")
    repo(AshPostgres.TestRepo)
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  field_policies do
    field_policy :* do
      authorize_if(always())
    end
  end

  actions do
    default_accept :*

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string)
  end

  relationships do
    has_many(:users, AshPostgres.Test.User)
    has_many(:posts, AshPostgres.Test.Post)
    has_many(:managers, AshPostgres.Test.Manager)
  end
end
