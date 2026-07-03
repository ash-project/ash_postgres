# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.BulkUpsertManagedRelationshipTest do
  @moduledoc """
  Regression test for a bulk-upsert managed-relationship association mismatch.

  When `Ash.bulk_create/4` runs a create action with `upsert? true` plus a
  `manage_relationship/3` change that creates a `has_one` child, each returned
  parent record must be correlated back to *its own* input changeset before the
  child is built (the child's foreign key is taken from the parent record).

  On PostgreSQL 17+ the upsert is implemented as a single `MERGE ... RETURNING`
  statement, whose output rows are **not** guaranteed to be in input order. The
  data layer previously fell back to zipping the returned rows against the input
  changesets *by position*, so a reordered `RETURNING` attached children to the
  wrong parents. Below PG 17 (`INSERT ... ON CONFLICT ... RETURNING`) the order
  happens to be preserved, which is why the bug only surfaces on the MERGE path.

  Each input `i` builds a parent and a child both tagged with `number: i`, so a
  correct association always joins a parent to the child carrying the same number.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.BulkUpsertParent

  defp inputs(count) do
    Enum.map(1..count, fn i ->
      %{number: i, name: "Parent #{i}", child: %{number: i}}
    end)
  end

  defp mismatches do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        AshPostgres.TestRepo,
        """
        SELECT p.number, c.number
        FROM bulk_upsert_parents p
        JOIN bulk_upsert_children c ON c.parent_id = p.id
        WHERE p.number <> c.number
        """,
        []
      )

    rows
  end

  describe "bulk upsert with managed has_one child (MERGE, PostgreSQL 17+)" do
    @describetag :postgres_17

    test "keeps each child attached to its own parent (fresh insert)" do
      bulk =
        Ash.bulk_create(inputs(150), BulkUpsertParent, :upsert_with_child,
          authorize?: false,
          return_errors?: true,
          stop_on_error?: false
        )

      assert bulk.status == :success
      assert bulk.errors == []
      assert mismatches() == []
    end

    test "keeps each child attached to its own parent (upsert onto existing rows)" do
      # Pre-populate the parents (without children) in a different physical order
      # than the later upsert input, maximizing the chance `MERGE ... RETURNING`
      # returns rows in an order that does not match the bulk input order.
      parents_only =
        inputs(150)
        |> Enum.map(&Map.delete(&1, :child))
        |> Enum.shuffle()

      Ash.bulk_create!(parents_only, BulkUpsertParent, :upsert_with_child, authorize?: false)

      bulk =
        Ash.bulk_create(inputs(150), BulkUpsertParent, :upsert_with_child,
          authorize?: false,
          return_errors?: true,
          stop_on_error?: false
        )

      assert bulk.status == :success
      assert bulk.errors == []
      assert mismatches() == []
    end
  end
end
