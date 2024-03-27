defmodule AshPostgres.Test.IntegerPost do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "integer_posts"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    integer_primary_key(:id)
    attribute(:title, :string, public?: true)
  end
end
