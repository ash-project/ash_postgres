# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.BulkDestroyAfterTransactionTest do
  @moduledoc """
  Tests for after_transaction hooks in bulk destroy operations with PostgreSQL.

  These tests verify the fix for after_transaction hooks running correctly
  when batch transactions fail in bulk_destroy with :stream strategy.

  Mirrors the :stream strategy Mnesia tests from the ash repo:
  ash/test/actions/bulk/bulk_destroy_after_transaction_test.exs
  """
  use AshPostgres.RepoCase, async: false

  import ExUnit.CaptureLog

  alias AshPostgres.Test.AfterTransactionPost

  require Ash.Query

  defp create_post(title) do
    AfterTransactionPost
    |> Ash.Changeset.for_create(:create, %{title: title})
    |> Ash.create!()
  end

  describe ":stream strategy" do
    test "after_action error with transaction: :all rolls back entire operation" do
      posts = for i <- 1..5, do: create_post("title_#{i}")
      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.bulk_destroy(
          :destroy_with_after_action_error_and_after_transaction,
          %{},
          strategy: :stream,
          transaction: :all,
          batch_size: 2,
          return_errors?: true
        )

      assert_receive {:after_action_error_hook_called}
      refute_receive {:after_action_error_hook_called}

      assert %Ash.BulkResult{errors: errors} = result
      assert result.status == :error
      assert length(errors) == 1

      # after_transaction NOT called because entire transaction rolled back
      refute_receive {:after_transaction_called, _}

      # Verify rollback: all posts still exist
      remaining = AfterTransactionPost |> Ash.read!()
      assert length(remaining) == 5
    end

    test "after_action error with transaction: :batch - after_transaction IS called" do
      posts = for i <- 1..5, do: create_post("title_#{i}")
      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.bulk_destroy(
          :destroy_with_after_action_error_and_after_transaction,
          %{},
          strategy: :stream,
          transaction: :batch,
          batch_size: 2,
          return_errors?: true
        )

      assert_receive {:after_action_error_hook_called}
      refute_receive {:after_action_error_hook_called}

      assert %Ash.BulkResult{errors: errors} = result
      assert result.status == :error
      assert length(errors) == 1

      assert_receive {:after_transaction_called, _}
      refute_receive {:after_transaction_called, _}

      # Verify rollback: all posts still exist (first batch rolled back, others never ran)
      remaining = AfterTransactionPost |> Ash.read!()
      assert length(remaining) == 5
    end

    test "hooks run outside batch transaction - no warning" do
      posts = for i <- 1..5, do: create_post("ok_#{i}")
      post_ids = Enum.map(posts, & &1.id)

      log =
        capture_log(fn ->
          result =
            AfterTransactionPost
            |> Ash.Query.filter(id in ^post_ids)
            |> Ash.bulk_destroy(
              :destroy_with_after_transaction,
              %{},
              strategy: :stream,
              batch_size: 2,
              return_records?: true,
              authorize?: false
              # transaction: :batch is the default
            )

          assert result.status == :success
          assert length(result.records) == 5
        end)

      # Verify the hook executed for all 5 records
      for _ <- 1..5, do: assert_receive({:postgres_after_transaction_called, _id})

      # Should NOT warn about hooks running inside a transaction
      refute log =~ "ongoing transaction still happening"
    end

    test "partial failure with transaction: :all rolls back all records" do
      # Prefixed titles for deterministic sorting: a_ before z_
      posts =
        for title <- ["a_ok_1", "a_ok_2", "a_ok_3", "z_fail_4", "z_fail_5"] do
          create_post(title)
        end

      post_ids = Enum.map(posts, & &1.id)

      {result, _} =
        with_log(fn ->
          AfterTransactionPost
          |> Ash.Query.filter(id in ^post_ids)
          |> Ash.Query.sort(:title)
          |> Ash.bulk_destroy(
            :destroy_with_conditional_after_action_error,
            %{},
            strategy: :stream,
            transaction: :all,
            batch_size: 2,
            return_errors?: true
          )
        end)

      assert_receive {:conditional_after_action_success, _}
      assert_receive {:conditional_after_action_success, _}
      assert_receive {:conditional_after_action_success, _}
      assert_receive {:conditional_after_action_error, _}
      refute_receive {:conditional_after_action_success, _}
      refute_receive {:conditional_after_action_error, _}

      # after_transaction NOT called because entire transaction rolled back
      refute_receive {:after_transaction_called, _}

      assert result.status == :error
      assert length(result.errors) == 1

      # All records unchanged - entire transaction rolled back due to :all
      remaining = AfterTransactionPost |> Ash.read!()
      assert length(remaining) == 5
    end

    test "partial failure with transaction: :batch commits first batch, rolls back second" do
      # Prefixed titles for deterministic sorting: a_ before z_
      posts =
        for title <- ["a_ok_1", "a_ok_2", "z_fail_3", "z_fail_4", "z_fail_5"] do
          create_post(title)
        end

      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.Query.sort(:title)
        |> Ash.bulk_destroy(
          :destroy_with_conditional_after_action_error,
          %{},
          strategy: :stream,
          transaction: :batch,
          batch_size: 2,
          return_errors?: true
        )

      # Batch 1 succeeds
      assert_receive {:conditional_after_action_success, _}
      assert_receive {:conditional_after_action_success, _}
      assert_receive {:conditional_after_transaction, {:ok, _}}
      assert_receive {:conditional_after_transaction, {:ok, _}}

      # Batch 2 fails
      assert_receive {:conditional_after_action_error, _}
      refute_receive {:conditional_after_action_success, _}
      refute_receive {:conditional_after_action_error, _}

      assert result.status == :partial_success
      assert length(result.errors) == 1

      # Second batch rolled back, after_transaction called with error (before stop_on_error)
      assert_receive {:conditional_after_transaction, {:error, _}}
      refute_receive {:conditional_after_transaction, _}

      # First batch deleted (committed), rest still exist
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.Query.sort(:title)
        |> Ash.read!()

      assert [%{title: "z_fail_3"}, %{title: "z_fail_4"}, %{title: "z_fail_5"}] = remaining
    end

    test "after_transaction error with transaction: :batch - records still deleted" do
      # Prefixed titles for deterministic sorting: a_ before z_
      posts =
        for title <- ["a_ok_1", "a_ok_2", "a_ok_3", "z_fail_4", "z_ok_5"] do
          create_post(title)
        end

      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.Query.sort(:title)
        |> Ash.bulk_destroy(
          :destroy_with_after_transaction_partial_failure,
          %{},
          strategy: :stream,
          transaction: :batch,
          batch_size: 2,
          return_errors?: true
        )

      # after_transaction hooks run OUTSIDE the transaction
      assert_receive {:after_transaction_partial_success, _}
      assert_receive {:after_transaction_partial_success, _}
      assert_receive {:after_transaction_partial_success, _}
      assert_receive {:after_transaction_partial_failure, _}
      refute_receive {:after_transaction_partial_success, _}
      refute_receive {:after_transaction_partial_failure, _}

      assert result.status == :partial_success
      assert length(result.errors) == 1

      # First 4 records deleted - after_transaction runs OUTSIDE tx
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.read!()

      assert [%{title: "z_ok_5"}] = remaining
    end

    test "after_transaction error with transaction: :all - entire operation rolls back" do
      # Prefixed titles for deterministic sorting: a_ before z_
      posts =
        for title <- ["a_ok_1", "a_ok_2", "a_ok_3", "z_fail_4", "z_ok_5"] do
          create_post(title)
        end

      post_ids = Enum.map(posts, & &1.id)

      {result, log} =
        with_log(fn ->
          AfterTransactionPost
          |> Ash.Query.filter(id in ^post_ids)
          |> Ash.Query.sort(:title)
          |> Ash.bulk_destroy(
            :destroy_with_after_transaction_partial_failure,
            %{},
            strategy: :stream,
            transaction: :all,
            batch_size: 2,
            return_errors?: true
          )
        end)

      # Hook runs INSIDE tx with :all (warning emitted)
      assert log =~ "after_transaction" and log =~ "ongoing transaction"

      for _ <- 1..3, do: assert_receive({:after_transaction_partial_success, _})
      assert_receive {:after_transaction_partial_failure, _}
      refute_receive {:after_transaction_partial_success, _}
      refute_receive {:after_transaction_partial_failure, _}

      assert result.status == :error
      assert length(result.errors) == 1

      # All records unchanged - entire transaction rolled back
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.read!()

      assert length(remaining) == 5
    end
  end

  describe ":atomic strategy" do
    test "hooks execute on success" do
      posts = for i <- 1..5, do: create_post("title_#{i}")
      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.bulk_destroy(
          :atomic_destroy_with_after_transaction,
          %{},
          strategy: :atomic,
          return_records?: true,
          return_errors?: true
        )

      assert result.status == :success
      assert length(result.records) == 5

      for _ <- 1..5 do
        assert_receive {:atomic_after_transaction_success, _id}
      end

      # All records deleted
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.read!()

      assert remaining == []
    end

    test "hooks run on failure" do
      posts = for i <- 1..5, do: create_post("title_#{i}")
      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.bulk_destroy(
          :destroy_with_after_action_error_and_after_transaction,
          %{},
          strategy: :atomic,
          return_errors?: true
        )

      assert_receive {:after_action_error_hook_called}
      refute_receive {:after_action_error_hook_called}

      assert result.status == :error
      assert length(result.errors) > 0

      # after_transaction receives error (runs OUTSIDE the transaction)
      assert_receive {:after_transaction_called, {:error, _}}
      refute_receive {:after_transaction_called, _}

      # Verify rollback - all records still exist
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.read!()

      assert length(remaining) == 5
    end

    test "after_action failure rolls back ALL records (single atomic transaction)" do
      # With :atomic, all 5 records are processed in ONE transaction.
      # If ANY after_action fails, ALL records roll back.
      posts =
        for title <- ["a_ok_1", "a_ok_2", "z_fail_3", "z_fail_4", "z_fail_5"] do
          create_post(title)
        end

      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.Query.sort(:title)
        |> Ash.bulk_destroy(
          :atomic_destroy_with_conditional_after_action_error,
          %{},
          strategy: :atomic,
          return_errors?: true
        )

      assert_receive {:atomic_after_action_success, _id}
      assert_receive {:atomic_after_action_success, _id}
      assert_receive {:atomic_after_action_error, _id}
      refute_receive {:atomic_after_action_success, _id}
      refute_receive {:atomic_after_action_error, _id}

      assert result.status == :error
      assert length(result.errors) == 1

      # after_transaction IS called with error
      assert_receive {:atomic_conditional_after_transaction, {:error, _}}
      refute_receive {:atomic_conditional_after_transaction, _}

      # All records rolled back - single atomic transaction
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.read!()

      assert length(remaining) == 5
    end

    test "partial failure sets status to :partial_success" do
      # With stop_on_error?: true, processing stops after first after_transaction error.
      # Note: after_transaction runs OUTSIDE the transaction, so data IS committed
      # even though the hook fails.
      posts =
        for title <- ["a_ok_1", "a_ok_2", "z_fail_3", "z_fail_4", "z_fail_5"] do
          create_post(title)
        end

      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.Query.sort(:title)
        |> Ash.bulk_destroy(
          :atomic_destroy_with_partial_failure,
          %{},
          strategy: :atomic,
          return_errors?: true
        )

      assert result.status == :partial_success
      assert length(result.errors) == 1

      assert_receive {:after_transaction_partial_success, _id}
      assert_receive {:after_transaction_partial_success, _id}
      assert_receive {:after_transaction_partial_failure, _id}
      refute_receive {:after_transaction_partial_success, _id}
      refute_receive {:after_transaction_partial_failure, _id}

      # All records were deleted - after_transaction runs OUTSIDE tx
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.read!()

      assert remaining == []
    end
  end

  describe ":atomic_batches strategy" do
    test "hooks execute across batches" do
      posts = for i <- 1..5, do: create_post("title_#{i}")
      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.bulk_destroy(
          :atomic_destroy_with_after_transaction,
          %{},
          strategy: :atomic_batches,
          batch_size: 2,
          return_records?: true,
          return_errors?: true
        )

      assert result.status == :success
      assert length(result.records) == 5

      for _ <- 1..5 do
        assert_receive {:atomic_after_transaction_success, _id}
      end

      # All records deleted
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.read!()

      assert remaining == []
    end

    test "hooks run on batch failure" do
      # Sorted order: a_ok_1, a_ok_2, z_fail_3, z_fail_4, z_fail_5
      # Batches (batch_size: 2): [a_ok_1, a_ok_2], [z_fail_3, z_fail_4], [z_fail_5]
      posts =
        for title <- ["a_ok_1", "a_ok_2", "z_fail_3", "z_fail_4", "z_fail_5"] do
          create_post(title)
        end

      post_ids = Enum.map(posts, & &1.id)

      result =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.Query.sort(:title)
        |> Ash.bulk_destroy(
          :atomic_destroy_with_conditional_after_action_error,
          %{},
          strategy: :atomic_batches,
          batch_size: 2,
          return_errors?: true
        )

      # Batch 1 succeeds
      assert_receive {:atomic_after_action_success, _}
      assert_receive {:atomic_after_action_success, _}
      assert_receive {:atomic_conditional_after_transaction, {:ok, _}}
      assert_receive {:atomic_conditional_after_transaction, {:ok, _}}

      # Batch 2 fails
      assert_receive {:atomic_after_action_error, _}
      refute_receive {:atomic_after_action_success, _}
      refute_receive {:atomic_after_action_error, _}

      assert result.status == :partial_success
      assert length(result.errors) == 1

      # after_transaction called for failed batch (runs OUTSIDE the transaction)
      assert_receive {:atomic_conditional_after_transaction, {:error, _}}
      refute_receive {:atomic_conditional_after_transaction, _}

      # First batch deleted, rest still exist
      remaining =
        AfterTransactionPost
        |> Ash.Query.filter(id in ^post_ids)
        |> Ash.Query.sort(:title)
        |> Ash.read!()

      assert [%{title: "z_fail_3"}, %{title: "z_fail_4"}, %{title: "z_fail_5"}] = remaining
    end
  end
end
