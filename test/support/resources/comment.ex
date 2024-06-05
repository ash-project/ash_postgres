defmodule AshPostgres.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  policies do
    bypass action_type(:read) do
      # Check that the comment is in the same org (via post) as actor
      authorize_if(relates_to_actor_via([:post, :organization, :users]))
    end
  end

  postgres do
    table "comments"
    repo(AshPostgres.TestRepo)

    references do
      reference(:post, on_delete: :delete, on_update: :update, name: "special_name_fkey")
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)
      argument(:rating, :map)

      change(manage_relationship(:rating, :ratings, on_missing: :ignore, on_match: :create))
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
    attribute(:likes, :integer, public?: true)
    attribute(:arbitrary_timestamp, :utc_datetime_usec, public?: true)
    create_timestamp(:created_at, writable?: true, public?: true)
  end

  aggregates do
    first(:post_category, :post, :category)
    count(:co_popular_comments, [:post, :popular_comments])
    count(:count_of_comments_containing_title, [:post, :comments_containing_title])
    list(:posts_for_comments_containing_title, [:post, :comments_containing_title, :post], :title)
  end

  relationships do
    belongs_to(:post, AshPostgres.Test.Post) do
      public?(true)
    end

    belongs_to(:author, AshPostgres.Test.Author) do
      public?(true)
    end

    has_many(:ratings, AshPostgres.Test.Rating,
      public?: true,
      destination_attribute: :resource_id,
      relationship_context: %{data_layer: %{table: "comment_ratings"}}
    )

    has_many(:popular_ratings, AshPostgres.Test.Rating,
      public?: true,
      destination_attribute: :resource_id,
      relationship_context: %{data_layer: %{table: "comment_ratings"}},
      filter: expr(score > 5)
    )

    has_many(:ratings_with_same_score_as_post, AshPostgres.Test.Rating,
      public?: true,
      destination_attribute: :resource_id,
      relationship_context: %{data_layer: %{table: "comment_ratings"}},
      filter: expr(parent(post.score) == score)
    )
  end
end
