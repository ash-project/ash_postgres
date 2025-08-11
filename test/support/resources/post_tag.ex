defmodule AshPostgres.Test.PostTag do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  require Ash.Sort

  postgres do
    table "post_tags"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  identities do
    identity(:unique_post_tag, [:post_id, :tag_id])
  end

  relationships do
    belongs_to :post, AshPostgres.Test.Post do
      primary_key?(true)
      public?(true)
      allow_nil?(false)
    end

    belongs_to :tag, AshPostgres.Test.Tag do
      primary_key?(true)
      public?(true)
      allow_nil?(false)
    end
  end
end
