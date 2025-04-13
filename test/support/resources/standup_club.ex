defmodule AshPostgres.Test.StandupClub do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  relationships do
    has_many(:comedians, AshPostgres.Test.Comedian, public?: true)
    has_many(:jokes, AshPostgres.Test.Joke, public?: true)
  end

  actions do
    defaults([:read])
  end

  aggregates do
    count(:punchline_count, [:jokes, :punchlines], public?: true)
  end

  postgres do
    table("standup_clubs")
    repo(AshPostgres.TestRepo)
  end
end
