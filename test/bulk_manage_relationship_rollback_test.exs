# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.BulkManageRelationshipRollbackTest do
  @moduledoc """
  Tests that bulk_create, bulk_update, and bulk_destroy properly roll back
  when manage_relationship fails during the after-action hooks phase.

  Bug: In `run_after_action_hooks/4` (present in create/bulk.ex, update/bulk.ex,
  and destroy/bulk.ex), when `manage_relationships` returns `{:error, error}`,
  the code returns `[{:error, error, changeset}]` WITHOUT calling
  `Ash.DataLayer.rollback`. The `run_after_actions` error path right above it
  DOES call rollback.

  With `transaction: :batch`, `process_results` runs OUTSIDE the batch
  transaction, so its `maybe_rollback` safety net cannot help — the parent
  record change is committed despite the child validation failure.

  All bulk tests use batch_size: 2 with 5 inputs. For bulk_create the 4th
  input has an invalid child, creating batches [1,2], [3,4*], [5] where
  batch 2 contains the failure. For bulk_update/destroy, all records receive
  the same invalid child input so every batch fails.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{RollbackChild, RollbackParent}

  # ============================================================================
  # bulk_create
  # ============================================================================

  describe "bulk_create: non-bulk control" do
    test "single create rolls back parent when child validation fails" do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(
          Ash.Changeset.for_create(RollbackParent, :create, %{
            name: "parent1",
            children: [%{title: nil}]
          }),
          authorize?: false
        )
      end

      assert [] == Ash.read!(RollbackParent, authorize?: false)
      assert [] == Ash.read!(RollbackChild, authorize?: false)
    end
  end

  describe "bulk_create: transaction :batch" do
    test "batch containing invalid child rolls back, other batches commit" do
      result =
        Ash.bulk_create(
          [
            %{name: "ok_1", children: [%{title: "c1"}]},
            %{name: "ok_2", children: [%{title: "c2"}]},
            %{name: "ok_3", children: [%{title: "c3"}]},
            %{name: "fail_4", children: [%{title: nil}]},
            %{name: "ok_5", children: [%{title: "c5"}]}
          ],
          RollbackParent,
          :create,
          batch_size: 2,
          transaction: :batch,
          rollback_on_error?: true,
          return_errors?: true,
          authorize?: false
        )

      assert result.status in [:error, :partial_success]

      parents = Ash.read!(RollbackParent, authorize?: false)
      parent_names = Enum.map(parents, & &1.name) |> Enum.sort()

      # Batch [ok_1, ok_2] commits, batch [ok_3, fail_4] rolls back,
      # subsequent batches may not run due to stop_on_error.
      assert "ok_3" not in parent_names,
             "ok_3 should be rolled back with fail_4, but found #{inspect(parent_names)}"

      children = Ash.read!(RollbackChild, authorize?: false)
      child_titles = Enum.map(children, & &1.title) |> Enum.sort()

      assert "c3" not in child_titles,
             "c3 should be rolled back with fail_4, but found #{inspect(child_titles)}"
    end
  end

  describe "bulk_create: transaction :all" do
    test "any invalid child rolls back ALL batches" do
      result =
        Ash.bulk_create(
          [
            %{name: "ok_1", children: [%{title: "c1"}]},
            %{name: "ok_2", children: [%{title: "c2"}]},
            %{name: "ok_3", children: [%{title: "c3"}]},
            %{name: "fail_4", children: [%{title: nil}]},
            %{name: "ok_5", children: [%{title: "c5"}]}
          ],
          RollbackParent,
          :create,
          batch_size: 2,
          transaction: :all,
          rollback_on_error?: true,
          return_errors?: true,
          authorize?: false
        )

      assert result.status == :error
      assert [] == Ash.read!(RollbackParent, authorize?: false)
      assert [] == Ash.read!(RollbackChild, authorize?: false)
    end
  end

  # ============================================================================
  # bulk_create upsert
  # ============================================================================

  describe "bulk_create upsert: transaction :batch" do
    test "batch containing invalid child rolls back, other batches commit" do
      for name <- ~w(ok_1 ok_2 ok_3 fail_4 ok_5) do
        Ash.create!(
          Ash.Changeset.for_create(RollbackParent, :create, %{name: name}),
          authorize?: false
        )
      end

      result =
        Ash.bulk_create(
          [
            %{name: "ok_1", children: [%{title: "c1"}]},
            %{name: "ok_2", children: [%{title: "c2"}]},
            %{name: "ok_3", children: [%{title: "c3"}]},
            %{name: "fail_4", children: [%{title: nil}]},
            %{name: "ok_5", children: [%{title: "c5"}]}
          ],
          RollbackParent,
          :upsert,
          batch_size: 2,
          transaction: :batch,
          rollback_on_error?: true,
          return_errors?: true,
          authorize?: false
        )

      assert result.status in [:error, :partial_success]

      # All 5 parents should still exist (upsert doesn't create new ones)
      assert length(Ash.read!(RollbackParent, authorize?: false)) == 5

      children = Ash.read!(RollbackChild, authorize?: false)
      child_titles = Enum.map(children, & &1.title) |> Enum.sort()

      # Batch [ok_1, ok_2] commits children, batch [ok_3, fail_4] rolls back,
      # subsequent batches may not run due to stop_on_error.
      assert "c3" not in child_titles,
             "c3 should be rolled back with fail_4, but found #{inspect(child_titles)}"
    end
  end

  describe "bulk_create upsert: transaction :all" do
    test "any invalid child rolls back ALL batches" do
      for name <- ~w(ok_1 ok_2 ok_3 fail_4 ok_5) do
        Ash.create!(
          Ash.Changeset.for_create(RollbackParent, :create, %{name: name}),
          authorize?: false
        )
      end

      result =
        Ash.bulk_create(
          [
            %{name: "ok_1", children: [%{title: "c1"}]},
            %{name: "ok_2", children: [%{title: "c2"}]},
            %{name: "ok_3", children: [%{title: "c3"}]},
            %{name: "fail_4", children: [%{title: nil}]},
            %{name: "ok_5", children: [%{title: "c5"}]}
          ],
          RollbackParent,
          :upsert,
          batch_size: 2,
          transaction: :all,
          rollback_on_error?: true,
          return_errors?: true,
          authorize?: false
        )

      assert result.status == :error
      assert length(Ash.read!(RollbackParent, authorize?: false)) == 5
      assert [] == Ash.read!(RollbackChild, authorize?: false)
    end
  end

  # ============================================================================
  # bulk_update (all strategies)
  # ============================================================================

  describe "bulk_update: non-bulk control" do
    test "single update rolls back when child validation fails" do
      parent =
        Ash.create!(
          Ash.Changeset.for_create(RollbackParent, :create, %{name: "original"}),
          authorize?: false
        )

      assert_raise Ash.Error.Invalid, fn ->
        parent
        |> Ash.Changeset.for_update(:update_with_children, %{
          name: "updated",
          children: [%{title: nil}]
        })
        |> Ash.update!(authorize?: false)
      end

      [reloaded] = Ash.read!(RollbackParent, authorize?: false)

      assert reloaded.name == "original",
             "Parent update should be rolled back, but name is #{inspect(reloaded.name)}"

      assert [] == Ash.read!(RollbackChild, authorize?: false)
    end
  end

  for strategy <- [[:stream], [:atomic, :stream], [:atomic_batches, :stream]] do
    describe "bulk_update strategy #{inspect(strategy)}: transaction :batch" do
      test "5 parents updated with invalid children, batch_size 2, all batches should rollback" do
        parents =
          for i <- 1..5 do
            Ash.create!(
              Ash.Changeset.for_create(RollbackParent, :create, %{name: "original_#{i}"}),
              authorize?: false
            )
          end

        result =
          parents
          |> Ash.bulk_update(
            :update_with_children,
            %{name: "updated", children: [%{title: nil}]},
            strategy: unquote(strategy),
            batch_size: 2,
            transaction: :batch,
            rollback_on_error?: true,
            return_errors?: true,
            authorize?: false
          )

        assert result.status in [:error, :partial_success]

        reloaded = Ash.read!(RollbackParent, authorize?: false)
        names = Enum.map(reloaded, & &1.name) |> Enum.sort()

        assert names == Enum.map(1..5, &"original_#{&1}"),
               "All updates should be rolled back, but found #{inspect(names)}"

        assert [] == Ash.read!(RollbackChild, authorize?: false)
      end
    end

    describe "bulk_update strategy #{inspect(strategy)}: transaction :all" do
      test "5 parents updated with invalid children, batch_size 2, everything rolls back" do
        parents =
          for i <- 1..5 do
            Ash.create!(
              Ash.Changeset.for_create(RollbackParent, :create, %{name: "original_#{i}"}),
              authorize?: false
            )
          end

        result =
          parents
          |> Ash.bulk_update(
            :update_with_children,
            %{name: "updated", children: [%{title: nil}]},
            strategy: unquote(strategy),
            batch_size: 2,
            transaction: :all,
            rollback_on_error?: true,
            return_errors?: true,
            authorize?: false
          )

        assert result.status == :error

        reloaded = Ash.read!(RollbackParent, authorize?: false)
        names = Enum.map(reloaded, & &1.name) |> Enum.sort()

        assert names == Enum.map(1..5, &"original_#{&1}"),
               "All updates should be rolled back, but found #{inspect(names)}"

        assert [] == Ash.read!(RollbackChild, authorize?: false)
      end
    end
  end

  # ============================================================================
  # bulk_destroy (all strategies)
  # ============================================================================

  describe "bulk_destroy: non-bulk control" do
    test "single destroy with invalid child argument rolls back (manage_relationship exercised)" do
      parent =
        Ash.create!(
          Ash.Changeset.for_create(RollbackParent, :create, %{name: "should_be_destroyed"}),
          authorize?: false
        )

      assert {:error, %Ash.Error.Invalid{}} =
               parent
               |> Ash.Changeset.for_destroy(:destroy_with_children, %{children: [%{title: nil}]})
               |> Ash.destroy(authorize?: false)

      # Parent should still exist because the transaction rolled back
      assert [%{name: "should_be_destroyed"}] = Ash.read!(RollbackParent, authorize?: false)
      assert [] == Ash.read!(RollbackChild, authorize?: false)
    end

    test "single destroy with valid child argument rolls back due to FK constraint" do
      # Creating children that belong_to a hard-deleted parent will always fail
      # at the DB level (FK constraint), so the transaction rolls back.
      parent =
        Ash.create!(
          Ash.Changeset.for_create(RollbackParent, :create, %{name: "should_be_destroyed"}),
          authorize?: false
        )

      assert {:error, %Ash.Error.Invalid{}} =
               parent
               |> Ash.Changeset.for_destroy(:destroy_with_children, %{
                 children: [%{title: "orphan_child"}]
               })
               |> Ash.destroy(authorize?: false)

      # Parent still exists because transaction rolled back
      assert [%{name: "should_be_destroyed"}] = Ash.read!(RollbackParent, authorize?: false)
      assert [] == Ash.read!(RollbackChild, authorize?: false)
    end
  end

  for strategy <- [[:stream], [:atomic, :stream], [:atomic_batches, :stream]] do
    describe "bulk_destroy strategy #{inspect(strategy)}: transaction :batch" do
      test "5 parents destroyed with invalid children, batch_size 2, all batches should rollback" do
        for i <- 1..5 do
          Ash.create!(
            Ash.Changeset.for_create(RollbackParent, :create, %{name: "parent_#{i}"}),
            authorize?: false
          )
        end

        result =
          RollbackParent
          |> Ash.read!(authorize?: false)
          |> Ash.bulk_destroy(
            :destroy_with_children,
            %{children: [%{title: nil}]},
            strategy: unquote(strategy),
            batch_size: 2,
            transaction: :batch,
            rollback_on_error?: true,
            return_errors?: true,
            authorize?: false
          )

        assert result.status in [:error, :partial_success]

        parents = Ash.read!(RollbackParent, authorize?: false)

        assert length(parents) == 5,
               "All destroys should be rolled back, but found #{length(parents)} parents"

        assert [] == Ash.read!(RollbackChild, authorize?: false)
      end
    end

    describe "bulk_destroy strategy #{inspect(strategy)}: transaction :all" do
      test "5 parents destroyed with invalid children, batch_size 2, everything rolls back" do
        for i <- 1..5 do
          Ash.create!(
            Ash.Changeset.for_create(RollbackParent, :create, %{name: "parent_#{i}"}),
            authorize?: false
          )
        end

        result =
          RollbackParent
          |> Ash.read!(authorize?: false)
          |> Ash.bulk_destroy(
            :destroy_with_children,
            %{children: [%{title: nil}]},
            strategy: unquote(strategy),
            batch_size: 2,
            transaction: :all,
            rollback_on_error?: true,
            return_errors?: true,
            authorize?: false
          )

        assert result.status == :error

        parents = Ash.read!(RollbackParent, authorize?: false)

        assert length(parents) == 5,
               "All destroys should be rolled back, but found #{length(parents)} parents"

        assert [] == Ash.read!(RollbackChild, authorize?: false)
      end
    end
  end
end
