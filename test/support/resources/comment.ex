defmodule AshPostgres.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "comments"
    repo AshPostgres.TestRepo

    references do
      reference(:post, on_delete: :delete, on_update: :update, name: "special_name_fkey")
    end
  end

  actions do
    read(:read)

    create :create do
      argument(:rating, :map)

      change(manage_relationship(:rating, :ratings, on_missing: :ignore, on_match: :create))
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string)
    attribute(:likes, :integer)
    attribute :arbitrary_timestamp, :utc_datetime_usec
  end

  relationships do
    belongs_to(:post, AshPostgres.Test.Post)
    belongs_to(:author, AshPostgres.Test.Author)

    has_many(:ratings, AshPostgres.Test.Rating,
      destination_field: :resource_id,
      relationship_context: %{data_layer: %{table: "comment_ratings"}}
    )
  end
end
