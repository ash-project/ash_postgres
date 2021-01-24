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
    uuid_primary_key(:id)
    attribute(:title, :string)
    attribute(:score, :integer)
    attribute(:public, :boolean)
    attribute(:category, :ci_string)
  end

  relationships do
    has_many(:comments, AshPostgres.Test.Comment, destination_field: :post_id)
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
