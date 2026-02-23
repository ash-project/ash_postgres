# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Subquery.Parent do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Subquery.ParentDomain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  alias AshPostgres.Test.Subquery.{Access, Child, Through}

  postgres do
    repo AshPostgres.TestRepo
    table "subquery_parent"
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:owner_email, :string, public?: true)
    attribute(:other_owner_email, :string, public?: true)
    attribute(:visible, :boolean, public?: true)
  end

  relationships do
    many_to_many :children, Child do
      public?(true)
      through(Through)
      source_attribute(:id)
      source_attribute_on_join_resource(:parent_id)
      destination_attribute(:id)
      destination_attribute_on_join_resource(:child_id)
      domain(AshPostgres.Test.Subquery.ChildDomain)
    end

    has_many(:accesses, Access) do
      public?(true)
    end
  end

  policies do
    policy [
      action(:read),
      expr(
        visible == true and
          (not is_nil(^actor(:email)) and
             (owner_email == ^actor(:email) or other_owner_email == ^actor(:email) or
                exists(accesses, email == ^actor(:email))))
      )
    ] do
      authorize_if(always())
    end
  end

  code_interface do
    define(:create)
    define(:read)

    define(:get_by_id, action: :read, get_by: :id)
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end
end
