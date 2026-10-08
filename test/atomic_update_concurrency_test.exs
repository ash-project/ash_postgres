# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.AtomicUpdateConcurrencyTest do
  @moduledoc """
  An update whose query has a limit or offset, or whose atomics need a join or `exists`, is
  run as `UPDATE ... FROM (SELECT <new values> ...)`, and a destroy like it as
  `DELETE ... USING (SELECT ...)`. The subquery has to lock the rows it reads, or a statement
  that waited on a concurrent writer acts on rows that no longer match its filter, and an
  update overwrites that writer's change with values computed from the row as it was before.

  Real concurrency needs two database connections, so these tests bypass the sandbox.
  """
  use AshPostgres.RepoCase, async: false

  require Ash.Query
  import Ash.Expr

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

  # The `UPDATE` statement run by `fun`.
  defp update_sql(fun) do
    parent = self()
    handler = "atomic-update-sql-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:ash_postgres, :test_no_sandbox_repo, :query],
      fn _, _, %{query: query}, _ ->
        if String.starts_with?(query, "UPDATE"), do: send(parent, {:update_sql, query})
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    assert_received {:update_sql, sql}
    sql
  end

  defp bulk_update_one(post, action, input) do
    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.limit(1)
    |> Ash.bulk_update!(action, input,
      context: @context,
      strategy: :atomic,
      return_errors?: true
    )
  end

  test "an update of other columns locks with FOR NO KEY UPDATE", %{post: post} do
    sql = update_sql(fn -> bulk_update_one(post, :increment_score, %{amount: 1}) end)

    assert sql =~ "FOR NO KEY UPDATE OF"
  end

  test "an update of a column in a unique index locks with FOR UPDATE", %{post: post} do
    sql = update_sql(fn -> bulk_update_one(post, :append_to_uniq_one, %{}) end)

    assert sql =~ "FOR UPDATE OF"
    refute sql =~ "NO KEY"
    assert TestNoSandboxRepo.get!(Post, post.id).uniq_one == "!"
  end

  # Writes `first_name` in a transaction held open until `fun` is waiting on it, then commits
  # and returns what `fun` returned.
  defp after_concurrent_rename(author, first_name, fun) do
    parent = self()

    first =
      Task.async(fn ->
        TestNoSandboxRepo.transaction(fn ->
          author
          |> Ash.Changeset.for_update(:update, %{first_name: first_name})
          |> Ash.Changeset.set_context(@context)
          |> Ash.update!()

          send(parent, :first_written)

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive :first_written, 5_000

    second = Task.async(fun)

    refute Task.yield(second, 300), "the second statement should be waiting on the first writer"

    send(first.pid, :commit)

    assert {:ok, :ok} = Task.await(first, 5_000)
    Task.await(second, 5_000)
  end

  defp create_author(first_name) do
    on_exit(fn -> TestNoSandboxRepo.delete_all(AshPostgres.Test.Author) end)

    AshPostgres.Test.Author
    |> Ash.Changeset.for_create(:create, %{first_name: first_name})
    |> Ash.Changeset.set_context(@context)
    |> Ash.create!()
  end

  # Two workers claiming the same row: once the first commits, the row no longer matches the
  # second's filter, so the second must not claim it too, even though its new values don't
  # read the row.
  test "an update re-checks its filter against a row a concurrent writer changed" do
    author = create_author("pending")

    result =
      after_concurrent_rename(author, "claimed by first", fn ->
        AshPostgres.Test.Author
        |> Ash.Query.filter(first_name == "pending")
        |> Ash.Query.limit(1)
        |> Ash.bulk_update!(:update, %{first_name: "claimed by second"},
          context: @context,
          strategy: :atomic,
          return_records?: true,
          return_errors?: true
        )
      end)

    assert result.records == []

    assert TestNoSandboxRepo.get!(AshPostgres.Test.Author, author.id).first_name ==
             "claimed by first"
  end

  test "a destroy re-checks its filter against a row a concurrent writer changed" do
    author = create_author("pending")

    result =
      after_concurrent_rename(author, "kept", fn ->
        AshPostgres.Test.Author
        |> Ash.Query.filter(first_name == "pending")
        |> Ash.Query.limit(1)
        |> Ash.bulk_destroy!(:destroy, %{},
          context: @context,
          strategy: :atomic,
          return_records?: true,
          return_errors?: true
        )
      end)

    assert result.records == []
    assert TestNoSandboxRepo.get(AshPostgres.Test.Author, author.id)
  end

  # Sorting on something other than the distinct field makes `AshSql.Distinct` move the
  # `DISTINCT ON` into a joined subquery, which keeps the filter there too.
  for {shape, sort} <- [{"distinct", []}, {"distinct with a different sort", [:first_name]}] do
    test "a #{shape} update re-checks its filter against a row a concurrent writer changed" do
      author = create_author("pending")

      result =
        after_concurrent_rename(author, "claimed by first", fn ->
          AshPostgres.Test.Author
          |> Ash.Query.filter(first_name == "pending")
          |> Ash.Query.distinct(:last_name)
          |> Ash.Query.sort(unquote(sort))
          |> Ash.bulk_update!(:update, %{first_name: "claimed by second"},
            context: @context,
            strategy: :atomic,
            return_records?: true,
            return_errors?: true
          )
        end)

      assert result.records == []

      assert TestNoSandboxRepo.get!(AshPostgres.Test.Author, author.id).first_name ==
               "claimed by first"
    end

    test "a #{shape} destroy re-checks its filter against a row a concurrent writer changed" do
      author = create_author("pending")

      result =
        after_concurrent_rename(author, "kept", fn ->
          AshPostgres.Test.Author
          |> Ash.Query.filter(first_name == "pending")
          |> Ash.Query.distinct(:last_name)
          |> Ash.Query.sort(unquote(sort))
          |> Ash.bulk_destroy!(:destroy, %{},
            context: @context,
            strategy: :atomic,
            return_records?: true,
            return_errors?: true
          )
        end)

      assert result.records == []
      assert TestNoSandboxRepo.get(AshPostgres.Test.Author, author.id)
    end

    test "a #{shape} update with a limit keeps a concurrent write", %{post: post} do
      assert score_after_concurrent_increment(post, fn ->
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.distinct(:title)
               |> Ash.Query.sort(unquote(sort |> Enum.map(fn _ -> :score end)))
               |> Ash.Query.limit(1)
               |> Ash.bulk_update!(:increment_score, %{amount: 1},
                 context: @context,
                 strategy: :atomic,
                 return_errors?: true
               )
             end) == 2
    end
  end

  describe "combination_of queries" do
    setup do
      query =
        Post
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(score < 1)),
          Ash.Query.Combination.union(filter: expr(title == "title"))
        ])

      %{query: query}
    end

    test "can't be updated", %{query: query} do
      assert %Ash.BulkResult{status: :error, errors: [error]} =
               Ash.bulk_update(query, :increment_score, %{amount: 1},
                 context: @context,
                 strategy: :atomic,
                 return_errors?: true
               )

      assert Exception.message(error) =~
               "update actions over `combination_of` queries are not supported"
    end

    test "can't be destroyed", %{query: query} do
      assert %Ash.BulkResult{status: :error, errors: [error]} =
               Ash.bulk_destroy(query, :destroy, %{},
                 context: @context,
                 strategy: :atomic,
                 return_errors?: true
               )

      assert Exception.message(error) =~
               "destroy actions over `combination_of` queries are not supported"
    end
  end
end
