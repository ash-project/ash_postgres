defmodule AshPostgres.Test.Tag do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("tags")
    repo(AshPostgres.TestRepo)
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)
      upsert?(true)
      upsert_identity(:name)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
  end

  identities do
    identity(:name, [:name])
  end
end
