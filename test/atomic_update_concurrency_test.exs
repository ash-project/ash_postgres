# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.AtomicUpdateConcurrencyTest do
  @moduledoc """
  An update whose query has a limit or offset, or whose atomics need a join or `exists`, is
  run as `UPDATE ... FROM (SELECT <new values> ...)`. The subquery has to lock the rows it
  computes from, or an update that waited on a concurrent writer overwrites that writer's
  change with values computed from the row as it was before.

  Real concurrency needs two database connections, so these tests bypass the sandbox.
  """
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  alias AshPostgres.Test.Post
  alias AshPostgres.TestNoSandboxRepo

  @context %{data_layer: %{repo: TestNoSandboxRepo}}

  setup do
    on_exit(fn -> TestNoSandboxRepo.delete_all(Post) end)

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", score: 0})
      |> Ash.Changeset.set_context(@context)
      |> Ash.create!()

    %{post: post}
  end

  # Increments the score in a transaction held open until `update` is waiting on it, then
  # commits and returns the score once both writes are done.
  defp score_after_concurrent_increment(post, update) do
    parent = self()

    first =
      Task.async(fn ->
        TestNoSandboxRepo.transaction(fn ->
          post
          |> Ash.Changeset.for_update(:increment_score, %{amount: 1})
          |> Ash.Changeset.set_context(@context)
          |> Ash.update!()

          send(parent, :first_written)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :first_written, 5_000

    second = Task.async(update)

    refute Task.yield(second, 300), "the second update should be waiting on the first writer"

    send(first.pid, :commit)

    assert {:ok, :ok} = Task.await(first, 5_000)
    Task.await(second, 5_000)

    TestNoSandboxRepo.get!(Post, post.id).score
  end

  test "an update through a code interface given an id keeps a concurrent write", %{post: post} do
    assert score_after_concurrent_increment(post, fn ->
             Post.increment_score!(post.id, 1, context: @context)
           end) == 2
  end

  test "an update over a query with a limit keeps a concurrent write", %{post: post} do
    assert score_after_concurrent_increment(post, fn ->
             Post
             |> Ash.Query.filter(id == ^post.id)
             |> Ash.Query.limit(1)
             |> Ash.bulk_update!(:increment_score, %{amount: 1},
               context: @context,
               strategy: :atomic,
               return_errors?: true
             )
           end) == 2
  end

  test "an update whose atomics read an aggregate keeps a concurrent write", %{post: post} do
    for title <- ["a", "b"] do
      AshPostgres.Test.Comment
      |> Ash.Changeset.for_create(:create, %{title: title, post_id: post.id})
      |> Ash.Changeset.set_context(@context)
      |> Ash.create!()
    end

    assert score_after_concurrent_increment(post, fn ->
             Post
             |> Ash.Query.filter(id == ^post.id)
             |> Ash.bulk_update!(:add_comment_count_to_score, %{},
               context: @context,
               strategy: :atomic,
               return_errors?: true
             )
           end) == 3
  end

  test "an update's lock doesn't block inserting a row that references it", %{post: post} do
    parent = self()

    update =
      Task.async(fn ->
        TestNoSandboxRepo.transaction(fn ->
          Post
          |> Ash.Query.filter(id == ^post.id)
          |> Ash.Query.limit(1)
          |> Ash.bulk_update!(:increment_score, %{amount: 1},
            context: @context,
            strategy: :atomic,
            return_errors?: true
          )

          send(parent, :updated)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :updated, 5_000

    # The foreign key check locks the post with `FOR KEY SHARE`, which a plain update's
    # `FOR NO KEY UPDATE` allows and `FOR UPDATE` doesn't.
    insert =
      Task.async(fn ->
        AshPostgres.Test.Comment
        |> Ash.Changeset.for_create(:create, %{title: "a", post_id: post.id})
        |> Ash.Changeset.set_context(@context)
        |> Ash.create!()
      end)

    assert {:ok, _} = Task.yield(insert, 1_000), "the insert should not wait on the update"

    send(update.pid, :commit)
    assert {:ok, :ok} = Task.await(update, 5_000)
  end

  test "an update whose atomics use exists keeps a concurrent write", %{post: post} do
    assert score_after_concurrent_increment(post, fn ->
             Post
             |> Ash.Query.filter(id == ^post.id)
             |> Ash.bulk_update!(:increment_score_unless_commented, %{},
               context: @context,
               strategy: :atomic,
               return_errors?: true
             )
           end) == 2
  end
end
