defmodule AshPostgres.Test.DbStringPoint do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("string_points")
    repo(AshPostgres.TestRepo)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:id])
      upsert?(true)
      upsert_identity(:id)
    end
  end

  attributes do
    attribute(:id, AshPostgres.Test.StringPoint) do
      public?(true)
      primary_key?(true)
      allow_nil?(false)
    end
  end

  identities do
    identity(:id, [:id])
  end
end
