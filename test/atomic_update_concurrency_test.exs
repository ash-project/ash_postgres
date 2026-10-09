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

  # A column of `AshPostgres.Test.LockKeyColumn` for each way an index can make it a key, or
  # not. PostgreSQL treats a column as a key when it's in a unique index with no expressions
  # and no `WHERE`, and an update through a subquery has to lock as strongly as the `UPDATE`
  # will: `FOR UPDATE` when it changes a key column, `FOR NO KEY UPDATE` otherwise.
  # {attribute, column, key?, why}
  @lock_key_columns [
    {:stock, "stock", false, "in no index"},
    {:rank, "rank", false, "only in a non-unique index"},
    {:label, "label", false, "only in a unique expression index"},
    {:alias_name, "alias_name", false, "only in a partial unique custom index"},
    {:nickname, "nickname", false, "only in a partial identity"},
    {:tag, "tag_text", false, "stored in a column that isn't indexed, unlike its name"},
    {:id, "id", true, "the primary key"},
    {:handle, "handle", true, "an identity key"},
    {:org_id, "org_id", true, "the tenant column added to unique indexes"},
    {:shop_id, "shop_id", true, "a directed atom field of a unique index"},
    {:code, "sku", true, "stored in a column named by a directed field"},
    {:barcode, "barcode", true, "a string field of a unique index"},
    {:serial, "serial", true, "a directed string field of a unique index"},
    {:tag_code, "tag", true, "stored in a column named like another attribute"}
  ]

  defp new_value(:id), do: Ash.UUID.generate()
  defp new_value(:org_id), do: Ash.UUID.generate()
  defp new_value(:shop_id), do: Ash.UUID.generate()
  defp new_value(:stock), do: 2
  defp new_value(:rank), do: 2
  defp new_value(_), do: "new"

  defp new_lock_key_column_row do
    id = Ash.UUID.generate()

    TestNoSandboxRepo.query!(
      """
      INSERT INTO lock_key_columns
        (id, org_id, stock, rank, shop_id, sku, barcode, serial, tag_text, tag, label,
         alias_name, handle, nickname)
      VALUES ($1, $2, 1, 1, $3, $4, $4, $4, $4, $4, $4, $4, $4, $4)
      """,
      [
        Ecto.UUID.dump!(id),
        Ecto.UUID.dump!(Ash.UUID.generate()),
        Ecto.UUID.dump!(Ash.UUID.generate()),
        "old-#{System.unique_integer([:positive])}"
      ]
    )

    id
  end

  defp dump(value) do
    case Ecto.UUID.dump(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  # Whether a plain `UPDATE` of `column` blocks `FOR KEY SHARE`, which it does when
  # PostgreSQL takes `FOR UPDATE` for it.
  defp postgres_treats_as_key?(attribute, column) do
    id = new_lock_key_column_row()
    parent = self()

    updater =
      Task.async(fn ->
        TestNoSandboxRepo.transaction(fn ->
          TestNoSandboxRepo.query!(
            "UPDATE lock_key_columns SET #{column} = $1 WHERE id = $2",
            [dump(new_value(attribute)), Ecto.UUID.dump!(id)]
          )

          send(parent, :updated)

          receive do
            :done -> :ok
          end
        end)
      end)

    assert_receive :updated, 5_000

    blocked? =
      "SELECT 1 FROM lock_key_columns WHERE id = $1 FOR KEY SHARE NOWAIT"
      |> TestNoSandboxRepo.query([Ecto.UUID.dump!(id)])
      |> case do
        {:ok, _} -> false
        {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}} -> true
      end

    send(updater.pid, :done)
    Task.await(updater, 5_000)
    blocked?
  end

  describe "the lock an update takes through a subquery" do
    setup do
      on_exit(fn -> TestNoSandboxRepo.query!("DELETE FROM lock_key_columns") end)
    end

    for {attribute, column, key?, why} <- @lock_key_columns do
      test "matches PostgreSQL's for #{column}, #{why}" do
        assert postgres_treats_as_key?(unquote(attribute), unquote(column)) == unquote(key?)

        id = new_lock_key_column_row()

        sql =
          update_sql(fn ->
            AshPostgres.Test.LockKeyColumn
            |> Ash.Query.filter(id == ^id)
            |> Ash.Query.limit(1)
            |> Ash.bulk_update!(:update, %{unquote(attribute) => new_value(unquote(attribute))},
              context: @context,
              strategy: :atomic,
              return_errors?: true
            )
          end)

        if unquote(key?) do
          assert sql =~ "FOR UPDATE OF"
          refute sql =~ "NO KEY"
        else
          assert sql =~ "FOR NO KEY UPDATE OF"
        end
      end
    end
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
