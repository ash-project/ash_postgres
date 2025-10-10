# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Subquery.Access do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Parent

  use Ash.Resource,
    domain: AshPostgres.Test.Subquery.ParentDomain,
    data_layer: AshPostgres.DataLayer,
    primary_read_warning?: false,
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
    attribute(:parent_id, :uuid, public?: true)
    attribute(:email, :string, public?: true)
  end

  code_interface do
    define(:create)
    define(:read)
  end

  relationships do
    belongs_to(:parent, Parent) do
      public?(true)
    end
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  actions do
    default_accept(:*)

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
