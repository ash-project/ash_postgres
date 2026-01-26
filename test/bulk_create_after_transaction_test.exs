# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.BulkCreateAfterTransactionTest do
  @moduledoc """
  Tests for after_transaction hooks in bulk create operations with PostgreSQL.

  These tests verify after_transaction hooks run correctly in bulk_create operations.

  Mirrors the Ash repo tests from:
  ash/test/actions/bulk/bulk_create_after_transaction_test.exs
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.AfterTransactionPost

  describe "transaction: :batch" do
    test "hooks handle empty result set" do
      result =
        Ash.bulk_create(
          [],
          AfterTransactionPost,
          :create_with_after_transaction,
          return_records?: true,
          authorize?: false
        )

      assert result.status == :success
      assert result.records == []
      refute_receive {:postgres_after_transaction_called, _}
    end

    test "hook error is captured in result" do
      result =
        Ash.bulk_create(
          [
            %{title: "a_ok_1"},
            %{title: "a_ok_2"},
            %{title: "a_ok_3"},
            %{title: "z_fail_4"},
            %{title: "z_fail_5"}
          ],
          AfterTransactionPost,
          :create_with_after_transaction_partial_failure,
          batch_size: 2,
          sorted?: true,
          return_records?: true,
          return_errors?: true,
          authorize?: false
        )

      # 4 records processed: 3 succeed, 1 fails (z_fail_5 never reached due to stop_on_error default)
      for _ <- 1..3, do: assert_receive({:create_after_transaction_partial_success, _})
      assert_receive {:create_after_transaction_partial_failure, _}
      refute_receive {:create_after_transaction_partial_failure, _}

      assert result.status == :partial_success
      assert result.error_count == 1
      assert length(result.errors) == 1

      # Verify records committed to DB (after_transaction runs after commit)
      posts = AfterTransactionPost |> Ash.Query.sort(:title) |> Ash.read!()
      assert length(posts) == 4
      assert Enum.map(posts, & &1.title) == ["a_ok_1", "a_ok_2", "a_ok_3", "z_fail_4"]
    end

    test "hooks work with return_notifications?: true" do
      result =
        Ash.bulk_create!(
          [
            %{title: "test1"},
            %{title: "test2"},
            %{title: "test3"},
            %{title: "test4"},
            %{title: "test5"}
          ],
          AfterTransactionPost,
          :create_with_after_transaction,
          batch_size: 2,
          return_records?: true,
          return_notifications?: true,
          authorize?: false
        )

      assert result.status == :success
      assert length(result.records) == 5

      for _ <- 1..5, do: assert_receive({:postgres_after_transaction_called, _})
    end

    test "after_action error with rollback - batch commits partially" do
      # Sorted order: a_ok_1, a_ok_2, z_fail_3, z_fail_4, z_fail_5
      # Batches (batch_size 2): [a_ok_1, a_ok_2], [z_fail_3, z_fail_4], [z_fail_5]
      result =
        Ash.bulk_create(
          [
            %{title: "a_ok_1"},
            %{title: "a_ok_2"},
            %{title: "z_fail_3"},
            %{title: "z_fail_4"},
            %{title: "z_fail_5"}
          ],
          AfterTransactionPost,
          :create_with_conditional_after_action_error,
          batch_size: 2,
          sorted?: true,
          return_errors?: true,
          authorize?: false
        )

      # Batch 1 succeeds
      assert_receive {:create_conditional_after_action_success, _}
      assert_receive {:create_conditional_after_action_success, _}
      assert_receive {:create_conditional_after_transaction, {:ok, _}}
      assert_receive {:create_conditional_after_transaction, {:ok, _}}

      # Batch 2 fails
      assert_receive {:create_conditional_after_action_error, _}
      refute_receive {:create_conditional_after_action_success, _}
      refute_receive {:create_conditional_after_action_error, _}

      assert result.status == :partial_success
      assert length(result.errors) == 1

      assert_receive {:create_conditional_after_transaction, {:error, _}}
      refute_receive {:create_conditional_after_transaction, _}

      # Verify final state:
      # - a_ok_1, a_ok_2: created (batch 1 committed)
      # - z_fail_3, z_fail_4, z_fail_5: not created (batch 2 rolled back, batch 3 not processed)
      final_records =
        AfterTransactionPost
        |> Ash.Query.sort(:title)
        |> Ash.read!()

      assert length(final_records) == 2
      titles = Enum.map(final_records, & &1.title)
      assert titles == ["a_ok_1", "a_ok_2"]
    end

    test "after_transaction error - batch still commits (runs outside tx)" do
      # Sorted order: a_ok_1, a_ok_2, a_ok_3, z_fail_4, z_ok_5
      # Batches (batch_size 2): [a_ok_1, a_ok_2], [a_ok_3, z_fail_4], [z_ok_5]
      result =
        Ash.bulk_create(
          [
            %{title: "a_ok_1"},
            %{title: "a_ok_2"},
            %{title: "a_ok_3"},
            %{title: "z_fail_4"},
            %{title: "z_ok_5"}
          ],
          AfterTransactionPost,
          :create_with_after_transaction_partial_failure,
          batch_size: 2,
          sorted?: true,
          return_errors?: true,
          authorize?: false
        )

      # after_transaction hooks run OUTSIDE the transaction
      assert_receive {:create_after_transaction_partial_success, _}
      assert_receive {:create_after_transaction_partial_success, _}
      assert_receive {:create_after_transaction_partial_success, _}
      assert_receive {:create_after_transaction_partial_failure, _}
      refute_receive {:create_after_transaction_partial_success, _}
      refute_receive {:create_after_transaction_partial_failure, _}

      assert result.status == :partial_success
      assert length(result.errors) == 1

      # First 4 records committed - after_transaction runs OUTSIDE tx
      final_records =
        AfterTransactionPost
        |> Ash.Query.sort(:title)
        |> Ash.read!()

      assert length(final_records) == 4
      titles = Enum.map(final_records, & &1.title)
      assert titles == ["a_ok_1", "a_ok_2", "a_ok_3", "z_fail_4"]
    end
  end

  describe "transaction: :all" do
    test "after_action error rolls back entire operation" do
      result =
        Ash.bulk_create(
          [
            %{title: "title_1"},
            %{title: "title_2"},
            %{title: "title_3"},
            %{title: "title_4"},
            %{title: "title_5"}
          ],
          AfterTransactionPost,
          :create_with_after_action_error_and_after_transaction,
          transaction: :all,
          batch_size: 2,
          return_errors?: true,
          authorize?: false
        )

      assert_receive {:create_after_action_error_hook_called}
      refute_receive {:create_after_action_error_hook_called}

      assert %Ash.BulkResult{errors: errors} = result
      assert result.status == :error
      assert length(errors) == 1

      # after_transaction NOT called because entire transaction rolled back
      refute_receive {:create_after_transaction_called, _}

      # Verify rollback: no records created
      assert AfterTransactionPost |> Ash.read!() |> length() == 0
    end

    @tag :capture_log
    test "partial failure rolls back all records" do
      # Sorted order: a_ok_1, a_ok_2, a_ok_3, z_fail_4, z_fail_5
      # With transaction: :all, the entire operation rolls back on first error
      result =
        Ash.bulk_create(
          [
            %{title: "a_ok_1"},
            %{title: "a_ok_2"},
            %{title: "a_ok_3"},
            %{title: "z_fail_4"},
            %{title: "z_fail_5"}
          ],
          AfterTransactionPost,
          :create_with_conditional_after_action_error,
          transaction: :all,
          batch_size: 2,
          sorted?: true,
          return_errors?: true,
          authorize?: false
        )

      assert_receive {:create_conditional_after_action_success, _}
      assert_receive {:create_conditional_after_action_success, _}
      assert_receive {:create_conditional_after_action_success, _}
      assert_receive {:create_conditional_after_action_error, _}
      refute_receive {:create_conditional_after_action_success, _}
      refute_receive {:create_conditional_after_action_error, _}

      assert result.status == :error
      assert length(result.errors) == 1

      # All records rolled back - entire transaction
      assert AfterTransactionPost |> Ash.read!() |> length() == 0
    end

    @tag :capture_log
    test "after_transaction error - entire operation rolls back" do
      # Sorted order: a_ok_1, a_ok_2, a_ok_3, z_fail_4, z_ok_5
      result =
        Ash.bulk_create(
          [
            %{title: "a_ok_1"},
            %{title: "a_ok_2"},
            %{title: "a_ok_3"},
            %{title: "z_fail_4"},
            %{title: "z_ok_5"}
          ],
          AfterTransactionPost,
          :create_with_after_transaction_partial_failure,
          transaction: :all,
          batch_size: 2,
          sorted?: true,
          return_errors?: true,
          authorize?: false
        )

      for _ <- 1..3, do: assert_receive({:create_after_transaction_partial_success, _})
      assert_receive {:create_after_transaction_partial_failure, _}
      refute_receive {:create_after_transaction_partial_success, _}
      refute_receive {:create_after_transaction_partial_failure, _}

      assert result.status == :error
      assert length(result.errors) == 1

      # All records rolled back - entire transaction
      assert AfterTransactionPost |> Ash.read!() |> length() == 0
    end
  end
end
