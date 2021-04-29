defmodule AshPostgres.Test.PostLink do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "post_links"
    repo AshPostgres.TestRepo
  end

  relationships do
    belongs_to :source_post, AshPostgres.Test.Post do
      required?(true)
      primary_key?(true)
    end

    belongs_to :destination_post, AshPostgres.Test.Post do
      required?(true)
      primary_key?(true)
    end
  end
end
