defmodule AshPostgres.PartitionTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.PartitionedPost

  test "seeding data works" do
    assert false == AshPostgres.Partitioning.existing_partition?(PartitionedPost, key: 1)
    assert :ok == AshPostgres.Partitioning.create_partition(PartitionedPost, key: 1)
    assert true == AshPostgres.Partitioning.existing_partition?(PartitionedPost, key: 1)

    Ash.Seed.seed!(%PartitionedPost{key: 1})

    assert :ok == AshPostgres.Partitioning.create_partition(PartitionedPost, key: 2)
    Ash.Seed.seed!(%PartitionedPost{key: 2})
  end
end
