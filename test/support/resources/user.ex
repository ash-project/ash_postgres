defmodule AshPostgres.Test.User do
  @moduledoc false
  use Ash.Resource, data_layer: AshPostgres.DataLayer

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:is_active, :boolean)
  end

  postgres do
    table "users"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    has_many(:accounts, AshPostgres.Test.Account)
  end
end
