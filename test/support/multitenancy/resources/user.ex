defmodule AshPostgres.MultitenancyTest.User do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
    attribute(:org_id, :uuid, public?: true)
  end

  postgres do
    table "users"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  multitenancy do
    # Tells the resource to use the data layer
    # multitenancy, in this case separate postgres schemas
    strategy(:attribute)
    attribute(:org_id)
    parse_attribute({__MODULE__, :parse_tenant, []})
    global?(true)
  end

  relationships do
    belongs_to(:org, AshPostgres.MultitenancyTest.Org) do
      public?(true)
    end

    has_many :posts, AshPostgres.MultitenancyTest.Post do
      public?(true)
    end
  end

  aggregates do
    list(:years_visited, :posts, :last_word)
    count(:count_visited, :posts)
  end

  def parse_tenant("org_" <> id), do: id
end
