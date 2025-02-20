defmodule AshPostgres.MultitenancyTest.CompositeKeyPost do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "composite_key"
    repo AshPostgres.TestRepo
  end

  multitenancy do
    strategy(:context)
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    integer_primary_key(:id)
    attribute(:title, :string, public?: true, allow_nil?: false, primary_key?: true)
  end

  relationships do
    belongs_to(:org, AshPostgres.MultitenancyTest.Org) do
      public?(true)
    end
  end
end
