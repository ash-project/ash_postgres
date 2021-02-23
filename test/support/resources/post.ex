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

    create :create do
      argument(:rating, :map)

      change(manage_relationship(:rating, :ratings, on_missing: :ignore, on_match: :create))
    end
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:title, :string)
    attribute(:score, :integer)
    attribute(:public, :boolean)
    attribute(:category, :ci_string)
  end

  relationships do
    has_many(:comments, AshPostgres.Test.Comment, destination_field: :post_id)

    has_many(:ratings, AshPostgres.Test.Rating,
      destination_field: :resource_id,
      context: %{data_layer: %{table: "post_ratings"}}
    )
  end

  aggregates do
    count(:count_of_comments, :comments)

    count :count_of_comments_called_match, :comments do
      filter(title: "match")
    end

    first :first_comment, :comments, :title do
      sort(title: :asc_nils_last)
    end
  end
end
