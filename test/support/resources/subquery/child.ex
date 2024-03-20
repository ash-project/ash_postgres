defmodule AshPostgres.Test.Subquery.Child do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Through

  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  postgres do
    repo AshPostgres.TestRepo
    table "subquery_child"
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:state, :string)
  end

  code_interface do

    define(:create)
    define(:read)
  end

  relationships do
    has_many :throughs, Through do
      source_attribute(:id)
      destination_attribute(:child_id)
    end
  end

  policies do
    policy [
      action(:read),
      expr(
        (not is_nil(^actor(:email)) and
           (exists(throughs.parent, owner_email == ^actor(:email)) or
              exists(throughs.parent, other_owner_email == ^actor(:email)) or
              exists(throughs.parent.accesses, email == ^actor(:email)))) or
          state in ["public", "open"]
      )
    ] do
      authorize_if(always())
    end
  end

  actions do
    default_accept :*

    defaults([:create, :read, :update, :destroy])
  end
end
