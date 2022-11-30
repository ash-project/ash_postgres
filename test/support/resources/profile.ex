defmodule AshPostgres.Test.Profile do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("profile")
    schema("profiles")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:description, :string)
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  relationships do
    belongs_to(:author, AshPostgres.Test.Author)
  end

  aggregates do
    first(:author_badges, :author, :badges)
  end
end
