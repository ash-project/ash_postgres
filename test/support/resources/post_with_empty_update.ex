defmodule AshPostgres.Test.PostWithEmptyUpdate do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  require Ash.Sort

  policies do
    policy action(:empty_update) do
      # force visiting the database
      authorize_if(expr(fragment("TRUE = FALSE")))
    end
  end

  postgres do
    table("posts")
    repo(AshPostgres.TestRepo)
    migrate? false
  end

  actions do
    defaults([:create, :read])

    update :empty_update do
      accept([])
    end
  end

  attributes do
    uuid_primary_key(:id, writable?: true)

    attribute(:title, :string) do
      public?(true)
      source(:title_column)
    end

    attribute :model, :tuple do
      constraints(
        fields: [
          alpha: [type: :float, description: "The alpha field"],
          beta: [type: :float, description: "The beta field"],
          t: [type: :float, description: "The t field"]
        ]
      )

      allow_nil?(false)
      default(fn -> {3.0, 3.0, 1.0} end)
    end
  end
end
