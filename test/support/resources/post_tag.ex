defmodule AshPostgres.Test.PostTag do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "posts_tags"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:update, :read, :destroy])

    create :create do
      primary?(true)
      upsert?(true)
      upsert_identity(:unique_position_per_post)
      upsert_fields([:tag_id])
    end
  end

  attributes do
    attribute :position, :integer do
      allow_nil?(false)
    end
  end

  relationships do
    belongs_to(:post, AshPostgres.Test.Post, primary_key?: true, allow_nil?: false)
    belongs_to(:tag, AshPostgres.Test.Tag, primary_key?: true, allow_nil?: false)
  end

  identities do
    identity(:unique_position_per_post, [:position, :post_id])
  end
end
