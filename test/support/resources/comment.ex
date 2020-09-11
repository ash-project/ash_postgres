defmodule AshPostgres.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "comments"
    repo AshPostgres.TestRepo
  end

  actions do
    read(:read)
    create(:create)
  end

  attributes do
    attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
    attribute(:title, :string)
  end

  relationships do
    belongs_to(:post, AshPostgres.Test.Post)
  end
end
