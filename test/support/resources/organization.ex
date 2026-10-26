# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Organization do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  postgres do
    table("orgs")
    repo(AshPostgres.TestRepo)

    calculations_to_sql(lower_department: "LOWER(department)")

    identity_index_names(unique_external_id: "orgs_name_external_id_index")
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end

  field_policies do
    field_policy :* do
      authorize_if(always())
    end
  end

  aggregates do
    count :no_cast_open_posts_count, :posts do
      filter(expr(status_enum_no_cast != :closed))
    end
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
    attribute(:department, :string, public?: true)
    attribute(:external_id, :string, public?: true)
    attribute(:external_ref, :string, public?: true)
  end

  calculations do
    calculate(:lower_department, :string, expr(fragment("LOWER(?)", department)))
  end

  identities do
    identity(:department, [:lower_department], field_names: [:department_slug])
    identity(:unique_external_id, [:name, :external_id], field_names: [:external_id])
    identity(:unique_external_ref, [:name, :external_ref], field_names: [:external_ref])
  end

  relationships do
    has_many(:users, AshPostgres.Test.User) do
      public?(true)
    end

    has_many(:posts, AshPostgres.Test.Post) do
      public?(true)
    end

    has_many(:managers, AshPostgres.Test.Manager) do
      public?(true)
    end
  end
end
