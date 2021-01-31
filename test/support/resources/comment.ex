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

    create :create do
      reject [:ratings] # Disallow editing of the relationship itself

      manage_related :ratings, :append # Now `ratings` can be used as an argument
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string)
  end

  relationships do
    belongs_to(:post, AshPostgres.Test.Post)

    has_many(:ratings, AshPostgres.Test.Rating,
      destination_field: :resource_id,
      context: %{data_layer: %{table: "comment_ratings"}}
    )
  end
end
