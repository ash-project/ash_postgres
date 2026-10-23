# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.LockTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post
  require Ash.Query

  setup do
    Application.put_env(:ash, :disable_async?, true)

    on_exit(fn ->
      Application.put_env(:ash, :disable_async?, false)
      AshPostgres.TestNoSandboxRepo.delete_all(Post)
    end)
  end

  test "lock conflicts raise appropriate errors" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "locked"})
      |> Ash.Changeset.set_context(%{data_layer: %{repo: AshPostgres.TestNoSandboxRepo}})
      |> Ash.create!()

    task1 =
      Task.async(fn ->
        AshPostgres.TestNoSandboxRepo.transaction(fn ->
          Post
          |> Ash.Query.lock("FOR UPDATE NOWAIT")
          |> Ash.Query.set_context(%{data_layer: %{repo: AshPostgres.TestNoSandboxRepo}})
          |> Ash.Query.filter(id == ^post.id)
          |> Ash.read!()

          :timer.sleep(1000)
          :ok
        end)
      end)

    task2 =
      Task.async(fn ->
        try do
          AshPostgres.TestNoSandboxRepo.transaction(fn ->
            :timer.sleep(100)

            Post
            |> Ash.Query.lock("FOR UPDATE NOWAIT")
            |> Ash.Query.set_context(%{data_layer: %{repo: AshPostgres.TestNoSandboxRepo}})
            |> Ash.Query.filter(id == ^post.id)
            |> Ash.read!()
          end)
        rescue
          e ->
            {:error, e}
        end
      end)

    assert [{:ok, :ok}, {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{}]}}] =
             Task.await_many([task1, task2], :infinity)
  end

  # `AshSql.Distinct` puts a `DISTINCT ON` that's a prefix of the sort on the query itself, and
  # otherwise moves it into a subquery joined back to the table.
  @distinct_shapes %{
    "the distinct as a prefix of the sort" => [sort: [title: :asc, score: :desc]],
    "a distinct sort" => [distinct_sort: [score: :desc], sort: [title: :asc]],
    "a sort that doesn't start with the distinct" => [sort: [score: :desc]]
  }

  for {shape, _} <- @distinct_shapes do
    describe "a read with distinct and #{shape}" do
      @describetag shape: shape
      @context %{data_layer: %{repo: AshPostgres.TestNoSandboxRepo}}

      setup do
        posts =
          for {title, score} <- [{"a", 1}, {"a", 2}, {"b", 3}] do
            Post
            |> Ash.Changeset.for_create(:create, %{title: title, score: score})
            |> Ash.Changeset.set_context(@context)
            |> Ash.create!()
          end

        %{posts: posts}
      end

      for lock <- [
            :for_update,
            "FOR UPDATE",
            "FOR NO KEY UPDATE",
            "FOR SHARE",
            "FOR KEY SHARE",
            "FOR UPDATE NOWAIT",
            "FOR UPDATE SKIP LOCKED"
          ] do
        test "can be locked with #{inspect(lock)}", %{shape: shape} do
          assert {:ok, [{"a", 2}, {"b", 3}]} =
                   AshPostgres.TestNoSandboxRepo.transaction(fn ->
                     shape
                     |> highest_score_per_title()
                     |> Ash.Query.lock(unquote(lock))
                     |> read_titles_and_scores()
                   end)
        end
      end

      test "can be locked with a limit, a filter and loads", %{shape: shape} do
        assert {:ok, [%{title: "a", score: 2, count_of_comments: 0}]} =
                 AshPostgres.TestNoSandboxRepo.transaction(fn ->
                   Post
                   |> Ash.Query.filter(score < 3)
                   |> highest_score_per_title(shape)
                   |> Ash.Query.limit(1)
                   |> Ash.Query.load(:count_of_comments)
                   |> Ash.Query.lock(:for_update)
                   |> Ash.read!()
                 end)
      end

      test "only locks the rows it returns", %{shape: shape, posts: [lowest_a, highest_a, _]} do
        in_open_transaction(
          fn ->
            shape
            |> highest_score_per_title()
            |> Ash.Query.lock(:for_update)
            |> Ash.read!()
          end,
          fn _ ->
            assert {:ok, [_]} = lock_post(lowest_a, "FOR UPDATE NOWAIT")

            assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{}]}} =
                     lock_post(highest_a, "FOR UPDATE NOWAIT")
          end
        )
      end

      test "returns the committed version of a row a concurrent writer changed", %{
        shape: shape,
        posts: [_, highest_a, _]
      } do
        assert {:ok, [{"a", 10}, {"b", 3}]} =
                 read_after_concurrent_update(highest_a, %{score: 10}, fn ->
                   shape
                   |> highest_score_per_title()
                   |> Ash.Query.lock(:for_update)
                   |> read_titles_and_scores()
                 end)
      end

      test "re-checks its filter against a row a concurrent writer changed", %{
        shape: shape,
        posts: [_, highest_a, _]
      } do
        assert {:ok, []} =
                 read_after_concurrent_update(highest_a, %{score: 10}, fn ->
                   Post
                   |> Ash.Query.filter(score < 3)
                   |> highest_score_per_title(shape)
                   |> Ash.Query.lock(:for_update)
                   |> read_titles_and_scores()
                 end)
      end
    end
  end

  defp highest_score_per_title(query \\ Post, shape) do
    Enum.reduce(@distinct_shapes[shape], Ash.Query.distinct(query, :title), fn
      {:sort, sort}, query -> Ash.Query.sort(query, sort)
      {:distinct_sort, sort}, query -> Ash.Query.distinct_sort(query, sort)
    end)
    |> Ash.Query.set_context(@context)
  end

  defp read_titles_and_scores(query) do
    query
    |> Ash.read!()
    |> Enum.map(&{&1.title, &1.score})
    |> Enum.sort()
  end

  defp lock_post(post, lock) do
    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.lock(lock)
    |> Ash.Query.set_context(@context)
    |> Ash.read()
  end

  # Runs `fun` in a transaction held open until `then` returns, and returns what `then` did.
  defp in_open_transaction(fun, then) do
    parent = self()

    task =
      Task.async(fn ->
        AshPostgres.TestNoSandboxRepo.transaction(fn ->
          send(parent, {:ran, fun.()})

          receive do
            :commit -> :ok
          end
        end)
      end)

    assert_receive {:ran, result}, 5_000

    try do
      then.(result)
    after
      send(task.pid, :commit)
      assert {:ok, :ok} = Task.await(task, 5_000)
    end
  end

  # Updates `post` in a transaction held open until `read` is waiting on it, then commits and
  # returns what `read` returned in its own transaction.
  defp read_after_concurrent_update(post, attrs, read) do
    in_open_transaction(
      fn ->
        post
        |> Ash.Changeset.for_update(:update, attrs)
        |> Ash.Changeset.set_context(@context)
        |> Ash.update!()
      end,
      fn _ ->
        task = Task.async(fn -> AshPostgres.TestNoSandboxRepo.transaction(read) end)
        refute Task.yield(task, 300), "the read should be waiting on the writer"
        task
      end
    )
    |> Task.await(5_000)
  end
end
