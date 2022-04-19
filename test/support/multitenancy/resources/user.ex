defmodule AshPostgres.MultitenancyTest.User do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string)
    attribute(:org_id, :uuid)
  end

  postgres do
    table "users"
    repo AshPostgres.TestRepo
  end

  actions do
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
    belongs_to(:org, AshPostgres.MultitenancyTest.Org)
  end

  def parse_tenant("org_" <> id), do: id
end
