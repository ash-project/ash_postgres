defmodule AshPostgres.Test.Tag do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  require Ash.Sort

  postgres do
    table "tags"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:read])

    create :create do
      accept(:*)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:importance, :integer, allow_nil?: false, default: 0, public?: true)
  end

  relationships do
    many_to_many :posts, AshPostgres.Test.Post do
      through(AshPostgres.Test.PostTag)
      public?(true)
    end

    has_one :latest_post, AshPostgres.Test.Post do
      public?(true)
      no_attributes?(true)
      filter(expr(tags.id == parent(id)))
      sort(created_at: :desc)
    end

    has_one :post_with_highest_score, AshPostgres.Test.Post do
      public?(true)
      no_attributes?(true)
      filter(expr(tags.id == parent(id)))
      sort(score_after_winning: :desc)
    end
  end
end
