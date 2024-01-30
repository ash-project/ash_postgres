defmodule AshPostgres.Test.Subquery.Access do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Parent

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  require Ash.Query

  postgres do
    repo AshPostgres.TestRepo
    table "subquery_access"
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:parent_id, :uuid)
    attribute(:email, :string)
  end

  code_interface do
    define_for(AshPostgres.Test.Subquery.ParentApi)

    define(:create)
    define(:read)
  end

  relationships do
    belongs_to(:parent, Parent)
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  actions do
    defaults([:create, :update, :destroy])

    read :read do
      primary?(true)

      prepare(fn query, %{actor: actor} ->
        # THIS CAUSES THE ERROR
        query
        |> Ash.Query.filter(parent.visible == true)
      end)
    end
  end
end
