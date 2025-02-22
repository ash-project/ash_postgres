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
  end

  calculations do
    calculate(:lower_department, :string, expr(fragment("LOWER(?)", department)))
  end

  identities do
    identity(:department, [:lower_department], field_names: [:department_slug])
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
