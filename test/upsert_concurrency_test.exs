# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.UpsertConcurrencyTest do
  @moduledoc """
  Upserts are implemented with `INSERT ... ON CONFLICT DO UPDATE`, which arbitrates concurrent
  inserts of the same key: the loser waits for the winner to commit and then takes the
  `DO UPDATE` branch. `MERGE` does not offer that guarantee (the loser fails with a unique
  violation), which is why it is not used for upserts. See
  https://github.com/ash-project/ash_postgres/issues/844.

  Real concurrency needs two database connections, so these tests bypass the sandbox.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post
  alias AshPostgres.TestNoSandboxRepo

  setup do
    on_exit(fn -> TestNoSandboxRepo.delete_all(Post) end)
  end

  defp upsert!(attrs) do
    Post
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.Changeset.set_context(%{data_layer: %{repo: TestNoSandboxRepo}})
    |> Ash.create!(upsert?: true, upsert_identity: :uniq_one_and_two, upsert_fields: [:title])
  end

  test "a concurrent upsert of the same key waits for the first writer and then updates" do
    parent = self()

    # Inserts the row and holds the transaction open until told to commit.
    first =
      Task.async(fn ->
        TestNoSandboxRepo.transaction(fn ->
          record = upsert!(%{title: "first", uniq_one: "one", uniq_two: "two"})
          send(parent, :first_written)

          receive do
            :commit -> record
          end
        end)
      end)

    assert_receive :first_written, 5_000

    # Conflicts with the uncommitted row, so this blocks until the first transaction commits.
    second = Task.async(fn -> upsert!(%{title: "second", uniq_one: "one", uniq_two: "two"}) end)

    refute Task.yield(second, 300), "the second upsert should be waiting on the first writer"

    send(first.pid, :commit)

    assert {:ok, first_record} = Task.await(first, 5_000)
    second_record = Task.await(second, 5_000)

    assert Ash.Resource.get_metadata(first_record, :upsert_action) == :insert
    assert second_record.id == first_record.id
    assert second_record.title == "second"
    assert Ash.Resource.get_metadata(second_record, :upsert_action) == :update

    assert TestNoSandboxRepo.aggregate(Post, :count) == 1
  end

  test "concurrent bulk upserts of the same keys all succeed" do
    inputs =
      Enum.map(1..300, fn i -> %{title: "title", uniq_one: "one#{i}", uniq_two: "two#{i}"} end)

    write = fn ->
      Ash.bulk_create(inputs, Post, :create,
        context: %{data_layer: %{repo: TestNoSandboxRepo}},
        return_errors?: true,
        stop_on_error?: false,
        upsert?: true,
        upsert_identity: :uniq_one_and_two,
        upsert_fields: [:title]
      )
    end

    results =
      1..4
      |> Enum.map(fn _ -> Task.async(write) end)
      |> Task.await_many(60_000)

    assert Enum.map(results, & &1.error_count) == [0, 0, 0, 0]
    assert Enum.map(results, & &1.status) == [:success, :success, :success, :success]
    assert TestNoSandboxRepo.aggregate(Post, :count) == 300
  end
end
