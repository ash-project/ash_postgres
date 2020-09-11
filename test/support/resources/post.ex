defmodule AshPostgres.Test.Post do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "posts"
    repo AshPostgres.TestRepo
  end

  actions do
    read(:read)
    create(:create)
  end

  attributes do
    attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
    attribute(:title, :string)
    attribute(:score, :integer)
    attribute(:public, :boolean)
  end

  relationships do
    has_many(:comments, AshPostgres.Test.Comment, destination_field: :post_id)
  end
end
