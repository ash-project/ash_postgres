defmodule AshPostgres.Test.Organization do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("orgs")
    repo(AshPostgres.TestRepo)
  end

  actions do
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
