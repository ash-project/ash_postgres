defmodule AshPostgres.Test.Subquery.Through do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Child
  alias AshPostgres.Test.Subquery.Parent
  alias AshPostgres.Test.Subquery.ParentApi

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  postgres do
    repo AshPostgres.TestRepo
    table "subquery_through"
  end

  attributes do
    attribute :parent_id, :uuid do
      primary_key?(true)
      allow_nil?(false)
    end

    attribute :child_id, :uuid do
      primary_key?(true)
      allow_nil?(false)
    end
  end

  code_interface do
    define_for(AshPostgres.Test.Subquery.ChildApi)

    define(:create)
    define(:read)
  end

  relationships do
    belongs_to :parent, Parent do
      api(ParentApi)
    end

    belongs_to :child, Child do
      source_attribute(:parent_id)
      destination_attribute(:id)
    end
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end
end
