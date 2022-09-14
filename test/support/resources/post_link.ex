defmodule AshPostgres.Test.PostLink do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "post_links"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  relationships do
    belongs_to :source_post, AshPostgres.Test.Post do
      allow_nil?(false)
      primary_key?(true)
    end

    belongs_to :destination_post, AshPostgres.Test.Post do
      allow_nil?(false)
      primary_key?(true)
    end
  end
end
