# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.AfterTransactionPost do
  @moduledoc """
  Test resource for after_transaction hooks in bulk operations.

  Used to verify the fix for after_transaction hooks running correctly
  when batch transactions fail in bulk_create, bulk_update, and bulk_destroy
  with :stream strategy.
  """
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "after_transaction_posts"
    repo(AshPostgres.TestRepo)
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, create: :*])

    # ========================================================================
    # Create Actions (for bulk_create testing)
    # ========================================================================

    # after_action returns error, after_transaction sends message.
    # Used to verify rollback and after_transaction execution.
    create :create_with_after_action_error_and_after_transaction do
      accept([:title])
      change(__MODULE__.CreateAfterActionErrorWithAfterTransaction)
    end

    # Simple after_transaction hook that sends a message on success.
    create :create_with_after_transaction do
      accept([:title])
      change(__MODULE__.SimpleAfterTransactionChange)
    end

    # after_action fails only for records with "fail" in title.
    # Used to test partial batch failures in bulk_create.
    create :create_with_conditional_after_action_error do
      accept([:title])
      change(__MODULE__.CreateConditionalAfterActionError)
    end

    # after_transaction fails for records with "fail" in title.
    # Used to test partial_success status when some records succeed and some fail.
    create :create_with_after_transaction_partial_failure do
      accept([:title])
      change(__MODULE__.CreateAfterTransactionPartialFailure)
    end

    # ========================================================================
    # Update Actions
    # ========================================================================

    update :update do
      accept([:title])
    end

    # Sets title to "UPDATED_BY_ACTION", then after_action returns error.
    # Used to verify rollback and after_transaction execution.
    update :update_with_after_action_error_and_after_transaction do
      change(__MODULE__.AfterActionErrorWithAfterTransaction)
    end

    # Simple after_transaction hook that sends a message on success.
    update :update_with_after_transaction do
      accept([:title])
      change(__MODULE__.SimpleAfterTransactionChange)
    end

    # after_action fails only for records with "fail" in ORIGINAL title.
    # Sets title to "UPDATED_TITLE" to verify rollback.
    update :update_with_conditional_after_action_error do
      change(__MODULE__.ConditionalAfterActionErrorWithAfterTransaction)
    end

    # Prepends "UPDATED_" to title.
    # after_transaction fails for records with "fail" in title.
    # Used to test behavior when hook runs outside vs inside transaction.
    update :update_with_after_transaction_partial_failure do
      change(__MODULE__.AfterTransactionFailsForSomeRecords)
    end

    # ========================================================================
    # Atomic Strategy Actions
    # ========================================================================

    # Simple atomic update with after_transaction hook for success testing.
    update :atomic_update_with_after_transaction do
      change(__MODULE__.AtomicAfterTransactionChange)
    end

    # Atomic update where after_transaction fails for records with "fail" in title.
    # Used to test partial_success with atomic strategies.
    update :atomic_update_with_partial_failure do
      change(__MODULE__.AtomicAfterTransactionPartialFailure)
    end

    # Atomic update where after_action fails conditionally for records with "fail" in title.
    # Causes batch rollback. Used to test partial_success with atomic_batches.
    update :atomic_update_with_conditional_after_action_error do
      change(__MODULE__.AtomicConditionalAfterActionError)
    end

    # ========================================================================
    # Destroy Actions (mirror update actions for bulk_destroy testing)
    # ========================================================================

    # after_action returns error, after_transaction sends message.
    # Used to verify rollback and after_transaction execution.
    destroy :destroy_with_after_action_error_and_after_transaction do
      change(__MODULE__.AfterActionErrorWithAfterTransaction)
    end

    # Simple after_transaction hook that sends a message on success.
    destroy :destroy_with_after_transaction do
      change(__MODULE__.SimpleAfterTransactionChange)
    end

    # after_action fails only for records with "fail" in ORIGINAL title.
    destroy :destroy_with_conditional_after_action_error do
      change(__MODULE__.ConditionalAfterActionErrorWithAfterTransaction)
    end

    # after_transaction fails for records with "fail" in title.
    # Used to test behavior when hook runs outside vs inside transaction.
    destroy :destroy_with_after_transaction_partial_failure do
      change(__MODULE__.AfterTransactionFailsForSomeRecords)
    end

    # Simple atomic destroy with after_transaction hook for success testing.
    destroy :atomic_destroy_with_after_transaction do
      change(__MODULE__.AtomicAfterTransactionChange)
    end

    # Atomic destroy where after_transaction fails for records with "fail" in title.
    # Used to test partial_success with atomic strategies.
    destroy :atomic_destroy_with_partial_failure do
      change(__MODULE__.AtomicAfterTransactionPartialFailure)
    end

    # Atomic destroy where after_action fails conditionally for records with "fail" in title.
    # Causes batch rollback. Used to test partial_success with atomic_batches.
    destroy :atomic_destroy_with_conditional_after_action_error do
      change(__MODULE__.AtomicConditionalAfterActionError)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)
    # Separate attribute for tracking updates - avoids pagination issues when sorting by title
    attribute(:status, :string, allow_nil?: true, public?: true, default: nil)
  end

  # ============================================================================
  # Change Modules
  # ============================================================================

  defmodule AfterActionErrorWithAfterTransaction do
    @moduledoc """
    Sets title to "UPDATED_BY_ACTION", then after_action returns error.
    after_transaction sends message to verify hook execution on error.
    """
    use Ash.Resource.Change

    def atomic(changeset, opts, context) do
      {:ok, change(changeset, opts, context)}
    end

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.force_change_attribute(:title, "UPDATED_BY_ACTION")
      |> Ash.Changeset.after_action(fn _changeset, _result ->
        send(self(), {:after_action_error_hook_called})
        {:error, "after_action hook error"}
      end)
      |> Ash.Changeset.after_transaction(fn _changeset, result ->
        send(self(), {:after_transaction_called, result})
        result
      end)
    end
  end

  defmodule SimpleAfterTransactionChange do
    @moduledoc """
    Simple after_transaction hook that sends a message on success.
    """
    use Ash.Resource.Change

    def atomic(changeset, opts, context) do
      {:ok, change(changeset, opts, context)}
    end

    def change(changeset, _opts, _context) do
      Ash.Changeset.after_transaction(changeset, fn _changeset, {:ok, result} ->
        send(self(), {:postgres_after_transaction_called, result.id})
        {:ok, result}
      end)
    end
  end

  defmodule ConditionalAfterActionErrorWithAfterTransaction do
    @moduledoc """
    Change module for testing partial batch failures.

    Behavior:
    - Sets status to "updated" (not title, to allow sorting by title)
    - after_action checks title for "fail" and returns error if found
    - after_transaction sends messages to verify hook execution

    Used to test rollback behavior when first batch succeeds and second batch fails.
    """
    use Ash.Resource.Change

    # Return :not_atomic to ensure after_action callbacks run for each record individually
    def atomic(_changeset, _opts, _context), do: :not_atomic

    def change(changeset, _opts, _context) do
      changeset
      # Set status (not title) to verify update - allows sorting by title
      |> Ash.Changeset.force_change_attribute(:status, "updated")
      |> Ash.Changeset.after_action(fn _changeset, result ->
        # Check title for "fail" to determine if this record should error
        if String.contains?(result.title || "", "fail") do
          send(self(), {:conditional_after_action_error, result.id})

          {:error,
           Ash.Error.Changes.InvalidAttribute.exception(
             field: :title,
             message: "conditional error for fail title"
           )}
        else
          send(self(), {:conditional_after_action_success, result.id})
          {:ok, result}
        end
      end)
      |> Ash.Changeset.after_transaction(fn _changeset, result ->
        send(self(), {:conditional_after_transaction, result})
        result
      end)
    end
  end

  defmodule AfterTransactionFailsForSomeRecords do
    @moduledoc """
    Change module where after_transaction hook returns an error for records with title containing "fail".
    Used to test partial_success status when some records succeed and some fail.
    Sets status to "updated" to verify the update (not title, to allow sorting by title).
    """
    use Ash.Resource.Change

    # Return :not_atomic to ensure per-record processing
    def atomic(_changeset, _opts, _context), do: :not_atomic

    def change(changeset, _opts, _context) do
      changeset
      # Set status (not title) to verify update - allows sorting by title
      |> Ash.Changeset.force_change_attribute(:status, "updated")
      |> Ash.Changeset.after_transaction(fn
        _changeset, {:ok, result} ->
          if String.contains?(result.title || "", "fail") do
            send(self(), {:after_transaction_partial_failure, result.id})
            {:error, "Hook failed for title containing 'fail'"}
          else
            send(self(), {:after_transaction_partial_success, result.id})
            {:ok, result}
          end

        _changeset, {:error, error} ->
          {:error, error}
      end)
    end
  end

  # ============================================================================
  # Atomic Strategy Change Modules
  # ============================================================================

  defmodule AtomicAfterTransactionChange do
    @moduledoc """
    Change module that supports atomic operations with after_transaction hook.
    Sets status to "updated" and sends message on success.
    Used for testing :atomic and :atomic_batches strategies.
    """
    use Ash.Resource.Change

    def atomic(changeset, opts, context) do
      {:ok, change(changeset, opts, context)}
    end

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.force_change_attribute(:status, "updated")
      |> Ash.Changeset.after_transaction(fn
        _changeset, {:ok, result} ->
          send(self(), {:atomic_after_transaction_success, result.id})
          {:ok, result}

        _changeset, {:error, error} ->
          send(self(), {:atomic_after_transaction_error, error})
          {:error, error}
      end)
    end
  end

  defmodule AtomicAfterTransactionPartialFailure do
    @moduledoc """
    Change module that supports atomic operations where after_transaction fails
    for records with "fail" in title. Used to test partial_success with atomic strategies.
    Sets status to "updated" to verify the update.
    """
    use Ash.Resource.Change

    def atomic(changeset, opts, context) do
      {:ok, change(changeset, opts, context)}
    end

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.force_change_attribute(:status, "updated")
      |> Ash.Changeset.after_transaction(fn
        _changeset, {:ok, result} ->
          if String.contains?(result.title || "", "fail") do
            send(self(), {:after_transaction_partial_failure, result.id})
            {:error, "Atomic hook failed for title containing 'fail'"}
          else
            send(self(), {:after_transaction_partial_success, result.id})
            {:ok, result}
          end

        _changeset, {:error, error} ->
          send(self(), {:after_transaction_partial_error, error})
          {:error, error}
      end)
    end
  end

  defmodule AtomicConditionalAfterActionError do
    @moduledoc """
    Change module that supports atomic operations where after_action fails
    conditionally for records with "fail" in title. Causes batch rollback.
    Used to test partial_success with atomic_batches where first batch succeeds
    and second batch fails with rollback.
    """
    use Ash.Resource.Change

    def atomic(changeset, opts, context) do
      {:ok, change(changeset, opts, context)}
    end

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.force_change_attribute(:status, "updated")
      |> Ash.Changeset.after_action(fn _changeset, result ->
        if String.contains?(result.title || "", "fail") do
          send(self(), {:atomic_after_action_error, result.id})

          {:error,
           Ash.Error.Changes.InvalidAttribute.exception(
             field: :title,
             message: "conditional error for fail title"
           )}
        else
          send(self(), {:atomic_after_action_success, result.id})
          {:ok, result}
        end
      end)
      |> Ash.Changeset.after_transaction(fn _changeset, result ->
        send(self(), {:atomic_conditional_after_transaction, result})
        result
      end)
    end
  end

  # ============================================================================
  # Create-Specific Change Modules
  # ============================================================================

  defmodule CreateAfterActionErrorWithAfterTransaction do
    @moduledoc """
    Create change that triggers after_action error with after_transaction hook.
    after_action returns error immediately after creation.
    after_transaction sends message to verify hook execution on error.
    """
    use Ash.Resource.Change

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.after_action(fn _changeset, _result ->
        send(self(), {:create_after_action_error_hook_called})
        {:error, "after_action hook error on create"}
      end)
      |> Ash.Changeset.after_transaction(fn _changeset, result ->
        send(self(), {:create_after_transaction_called, result})
        result
      end)
    end
  end

  defmodule CreateConditionalAfterActionError do
    @moduledoc """
    Create change module for testing partial batch failures in bulk_create.

    Behavior:
    - after_action checks title for "fail" and returns error if found
    - after_transaction sends messages to verify hook execution

    Used to test rollback behavior when first batch succeeds and second batch fails.
    """
    use Ash.Resource.Change

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.after_action(fn _changeset, result ->
        # Check title for "fail" to determine if this record should error
        if String.contains?(result.title || "", "fail") do
          send(self(), {:create_conditional_after_action_error, result.id})

          {:error,
           Ash.Error.Changes.InvalidAttribute.exception(
             field: :title,
             message: "conditional error for fail title on create"
           )}
        else
          send(self(), {:create_conditional_after_action_success, result.id})
          {:ok, result}
        end
      end)
      |> Ash.Changeset.after_transaction(fn _changeset, result ->
        send(self(), {:create_conditional_after_transaction, result})
        result
      end)
    end
  end

  defmodule CreateAfterTransactionPartialFailure do
    @moduledoc """
    Create change module where after_transaction hook returns an error for records
    with title containing "fail". Used to test partial_success status in bulk_create
    when some records succeed and some fail in after_transaction.
    """
    use Ash.Resource.Change

    def change(changeset, _opts, _context) do
      changeset
      |> Ash.Changeset.after_transaction(fn
        _changeset, {:ok, result} ->
          if String.contains?(result.title || "", "fail") do
            send(self(), {:create_after_transaction_partial_failure, result.id})
            {:error, "Hook failed for title containing 'fail' on create"}
          else
            send(self(), {:create_after_transaction_partial_success, result.id})
            {:ok, result}
          end

        _changeset, {:error, error} ->
          {:error, error}
      end)
    end
  end
end
