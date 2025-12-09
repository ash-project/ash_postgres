defmodule AshPostgres.Test.PartitionedPost do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "partitioned_posts"
    repo AshPostgres.TestRepo

    partitioning do
      method(:list)
      attribute(:key)
    end
  end

  actions do
    default_accept(:*)

    defaults([:read, :destroy])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)

    attribute(:key, :integer, allow_nil?: false, primary_key?: true, default: 1)
  end
end
