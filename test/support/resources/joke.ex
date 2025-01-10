defmodule AshPostgres.Test.Joke do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key(:id)
    attribute(:text, :string, public?: true)
    attribute(:is_good, :boolean, default: false, public?: true)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  relationships do
    belongs_to(:comedian, AshPostgres.Test.Comedian, public?: true)
  end

  actions do
    defaults([:read])

    create :create do
      accept [:text, :is_good, :comedian_id]
    end
  end

  code_interface do
    define(:create)
  end

  postgres do
    table("jokes")
    repo(AshPostgres.TestRepo)
  end
end
