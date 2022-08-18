defmodule AshPostgres.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "comments"
    repo(AshPostgres.TestRepo)

    references do
      reference(:post, on_delete: :delete, on_update: :update, name: "special_name_fkey")
    end
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)
      argument(:rating, :map)

      change(manage_relationship(:rating, :ratings, on_missing: :ignore, on_match: :create))
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string)
    attribute(:likes, :integer)
    attribute(:arbitrary_timestamp, :utc_datetime_usec)
    create_timestamp(:created_at, writable?: true)
  end

  aggregates do
    first(:post_category, :post, :category)
    count(:co_popular_comments, [:post, :popular_comments])
  end

  relationships do
    belongs_to(:post, AshPostgres.Test.Post)
    belongs_to(:author, AshPostgres.Test.Author)

    has_many(:ratings, AshPostgres.Test.Rating,
      destination_attribute: :resource_id,
      relationship_context: %{data_layer: %{table: "comment_ratings"}}
    )

    has_many(:popular_ratings, AshPostgres.Test.Rating,
      destination_attribute: :resource_id,
      relationship_context: %{data_layer: %{table: "comment_ratings"}},
      filter: expr(score > 5)
    )
  end
end
