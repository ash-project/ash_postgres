defmodule AshPostgres.Test.Punchline do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key(:id)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  relationships do
    belongs_to(:joke, AshPostgres.Test.Joke, public?: true)
  end

  actions do
    defaults([:read])
  end

  postgres do
    table("punchlines")
    repo(AshPostgres.TestRepo)
  end
end
