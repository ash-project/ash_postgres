defmodule AshPostgres.Test.IntegerPost do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "integer_posts"
    repo AshPostgres.TestRepo
  end

  actions do
    read(:read)
    create(:create)
  end

  attributes do
    integer_primary_key(:id)
    attribute(:title, :string)
  end
end
