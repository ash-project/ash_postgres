defmodule AshPostgres.Test.Comedian do
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
    has_many(:jokes, AshPostgres.Test.Joke, public?: true)

    has_many :parent_parent_jokes, AshPostgres.Test.Joke do
      filter expr(exists(comedian, id == parent(parent(id))))
    end
  end

  calculations do
    calculate(:has_jokes_mod, :boolean, AshPostgres.Test.Comedian.HasJokes)
    calculate(:has_jokes_expr, :boolean, expr(has_jokes_mod == true))
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name])
    end
  end

  code_interface do
    define(:create)
  end

  postgres do
    table("comedians")
    repo(AshPostgres.TestRepo)
  end
end

defmodule AshPostgres.Test.Comedian.HasJokes do
  use Ash.Resource.Calculation

  @impl true
  def load(_, _, _) do
    [:jokes]
  end

  @impl true
  def calculate(comedians, _, _) do
    Enum.map(comedians, fn %{jokes: jokes} ->
      Enum.any?(jokes)
    end)
  end
end
