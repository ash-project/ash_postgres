defmodule AshPostgres.Test.User do
  @moduledoc false
  use Ash.Resource, data_layer: AshPostgres.DataLayer

  actions do
    defaults([:create, :read, :update, :destroy])

    read :active do
      filter(expr(active))
    end
  end

  calculations do
    calculate(:active, :boolean, expr(is_active == true))
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:is_active, :boolean)
    attribute(:name, :string)
  end

  postgres do
    table "users"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to :organization, AshPostgres.Test.Organization do
      attribute_writable?(true)
    end

    has_many(:accounts, AshPostgres.Test.Account)
  end
end
