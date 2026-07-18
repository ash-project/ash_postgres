# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationGenerator.OperationDepsTest do
  @moduledoc """
  Unit tests for `AshPostgres.MigrationGenerator.OperationDeps`, the
  dependency-graph model used to order migration operations.
  """
  use ExUnit.Case, async: true

  alias AshPostgres.MigrationGenerator.Operation
  alias AshPostgres.MigrationGenerator.OperationDeps

  describe "table existence" do
    test "table_ready from CreateTable, RenameTable, or MoveTableSchema each satisfy an AddAttribute on that table" do
      consumer = %Operation.AddAttribute{
        table: "posts",
        schema: nil,
        attribute: %{source: :title, primary_key?: false}
      }

      [required_fact] =
        OperationDeps.requires(consumer) |> Enum.filter(&match?({:table_ready, _}, &1))

      for provider <- [
            %Operation.CreateTable{table: "posts", schema: nil},
            %Operation.RenameTable{old_table: "old_posts", table: "posts", schema: nil},
            %Operation.MoveTableSchema{table: "posts", old_schema: "x", new_schema: nil}
          ] do
        assert required_fact in OperationDeps.provides(provider),
               "expected #{inspect(provider.__struct__)} to satisfy AddAttribute's table_ready requirement"
      end
    end
  end

  describe "same-table column existence" do
    test "AlterAttribute's column_ready requirement is satisfied by the AddAttribute that created the column" do
      add = %Operation.AddAttribute{
        table: "posts",
        schema: nil,
        attribute: %{source: :title, primary_key?: false}
      }

      alter = %Operation.AlterAttribute{
        table: "posts",
        schema: nil,
        old_attribute: %{source: :title},
        new_attribute: %{source: :title}
      }

      [column_ready_fact] =
        OperationDeps.provides(add) |> Enum.filter(&match?({:column_ready, _}, &1))

      assert column_ready_fact in OperationDeps.requires(alter)
    end
  end

  describe "cross-table structural FK" do
    test "an AddAttribute with a structural reference is satisfied by the referenced table's column and unique index" do
      referenced_column = %Operation.AddAttribute{
        table: "posts",
        schema: nil,
        attribute: %{source: :id, primary_key?: true}
      }

      referenced_index = %Operation.AddUniqueIndex{
        table: "posts",
        schema: nil,
        identity: %{keys: [:id], where: nil, base_filter: nil}
      }

      referencing_attribute = %Operation.AddAttribute{
        table: "comments",
        schema: nil,
        attribute: %{
          source: :post_id,
          primary_key?: false,
          references: %{table: "posts", destination_attribute: :id, schema: "public"}
        }
      }

      requires = OperationDeps.requires(referencing_attribute)

      [column_fact] =
        OperationDeps.provides(referenced_column) |> Enum.filter(&match?({:column_ready, _}, &1))

      [index_fact] =
        OperationDeps.provides(referenced_index)
        |> Enum.filter(&match?({:column_unique_index_created, _}, &1))

      assert column_fact in requires
      assert index_fact in requires
    end

    test "reference.schema (\"public\" string) and a table's own nil schema normalize to the same fact key" do
      # attribute.references.schema is loaded from the snapshot as an explicit
      # "public" string, while a resource's own `schema` option defaults to
      # `nil` for the default schema. Both must resolve to the same fact key,
      # or a real cross-table FK dependency silently disappears.
      provider_op = %Operation.AddAttribute{
        table: "posts",
        schema: nil,
        attribute: %{source: :id, primary_key?: true}
      }

      consumer_op = %Operation.AddAttribute{
        table: "comments",
        schema: nil,
        attribute: %{
          source: :post_id,
          primary_key?: false,
          references: %{table: "posts", destination_attribute: :id, schema: "public"}
        }
      }

      [provided_fact] =
        OperationDeps.provides(provider_op) |> Enum.filter(&match?({:column_ready, _}, &1))

      assert provided_fact in OperationDeps.requires(consumer_op)
    end
  end

  describe "unique index where/base_filter columns" do
    test "a filtered identity requires table_columns_settled (can't know which columns the raw SQL filter touches)" do
      filtered = %Operation.AddUniqueIndex{
        table: "posts",
        schema: nil,
        identity: %{keys: [:seq], where: "archived_at IS NULL", base_filter: nil},
        insert_after_attribute_source: nil
      }

      plain = %Operation.AddUniqueIndex{
        table: "posts",
        schema: nil,
        identity: %{keys: [:seq], where: nil, base_filter: nil},
        insert_after_attribute_source: nil
      }

      assert {:table_columns_settled, {"public", "posts"}} in OperationDeps.requires(filtered)
      refute {:table_columns_settled, {"public", "posts"}} in OperationDeps.requires(plain)
    end

    test "a plain (unfiltered) identity referencing a self-FK attribute does not require table_columns_settled (regression: issue #236 self-reference cycle)" do
      # A self-referencing belongs_to's FK attribute (e.g. `follows`) can be
      # the *last* AddAttribute for the table, so requiring "any attribute
      # added" here would create a cycle against that attribute's own
      # dependency on this very index. Only filtered identities take the
      # broader (and unavoidably imprecise) margin.
      op = %Operation.AddUniqueIndex{
        table: "template_phase",
        schema: nil,
        identity: %{keys: [:id], where: nil, base_filter: nil},
        insert_after_attribute_source: nil
      }

      refute {:table_columns_settled, {"public", "template_phase"}} in OperationDeps.requires(op)
    end
  end

  describe "custom index name collisions" do
    test "RemoveCustomIndex and AddCustomIndex sharing an explicit name are linked" do
      remove = %Operation.RemoveCustomIndex{
        table: "users",
        schema: nil,
        index: %{name: "users_active_name_index", fields: []},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      add = %Operation.AddCustomIndex{
        table: "users",
        schema: nil,
        index: %{name: "users_active_name_index"},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      [fact] =
        OperationDeps.provides(remove) |> Enum.filter(&match?({:custom_index_removed, _}, &1))

      assert fact in OperationDeps.requires(add)
    end

    test "two differently-shaped unnamed indexes are NOT spuriously linked by a shared nil name" do
      # Regression: an auto-named (nil `name:`) index previously collapsed to
      # the same `{schema, table, nil}` fact key as any other unnamed index on
      # the same table, incorrectly coupling unrelated index changes.
      remove = %Operation.RemoveCustomIndex{
        table: "posts",
        schema: nil,
        index: %{name: nil, fields: []},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      add = %Operation.AddCustomIndex{
        table: "posts",
        schema: nil,
        index: %{name: nil},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      refute Enum.any?(
               OperationDeps.provides(remove),
               &match?({:custom_index_removed, _}, &1)
             )

      refute Enum.any?(OperationDeps.requires(add), &match?({:custom_index_removed, _}, &1))
    end
  end

  describe "down-sequence validity for renames" do
    # A generated migration's `down` is the same operation order reversed,
    # rendering each operation's `down/1` (see the moduledoc). So even though
    # Postgres itself doesn't need an index/constraint removed before a
    # rename, RenameAttribute still has to run after these — otherwise
    # `down` would recreate the old index/unique-constraint (referencing the
    # old column name) before the rename's `down` restores that name.

    test "RenameAttribute requires column_custom_index_removed, satisfied by a RemoveCustomIndex whose fields include that column" do
      remove = %Operation.RemoveCustomIndex{
        table: "posts",
        schema: nil,
        index: %{name: nil, fields: [:title]},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      rename = %Operation.RenameAttribute{
        table: "posts",
        schema: nil,
        old_attribute: %{source: :title},
        new_attribute: %{source: :title_short}
      }

      [fact] =
        OperationDeps.provides(remove)
        |> Enum.filter(&match?({:column_custom_index_removed, _}, &1))

      assert fact in OperationDeps.requires(rename)
    end

    test "RenameAttribute is NOT satisfied by a RemoveCustomIndex covering a different column" do
      remove = %Operation.RemoveCustomIndex{
        table: "posts",
        schema: nil,
        index: %{name: nil, fields: [:body]},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      rename = %Operation.RenameAttribute{
        table: "posts",
        schema: nil,
        old_attribute: %{source: :title},
        new_attribute: %{source: :title_short}
      }

      [fact] =
        OperationDeps.provides(remove)
        |> Enum.filter(&match?({:column_custom_index_removed, _}, &1))

      refute fact in OperationDeps.requires(rename)
    end

    test "RenameAttribute requires column_unique_index_removed, satisfied by the RemoveUniqueIndex that covered the old column name" do
      remove_index = %Operation.RemoveUniqueIndex{
        table: "posts",
        schema: nil,
        identity: %{keys: [:title]}
      }

      rename = %Operation.RenameAttribute{
        table: "posts",
        schema: nil,
        old_attribute: %{source: :title},
        new_attribute: %{source: :title_short}
      }

      [fact] =
        OperationDeps.provides(remove_index)
        |> Enum.filter(&match?({:column_unique_index_removed, _}, &1))

      assert fact in OperationDeps.requires(rename)
    end

    test "RemoveAttribute requires column_check_constraint_removed, satisfied by the RemoveCheckConstraint that covered it" do
      # Confirmed by a real generated migration (see migration_generator_test.exs
      # "check constraint and column removed together"): RemoveCheckConstraint
      # must run before RemoveAttribute in `up`, or `down` tries to recreate
      # the constraint (RemoveCheckConstraint.down) before the column it
      # covers exists again (RemoveAttribute.down hasn't run yet in the
      # reversed sequence) — a real Postgres "column does not exist" error.
      remove_constraint = %Operation.RemoveCheckConstraint{
        table: "posts",
        schema: nil,
        constraint: %{attribute: [:title]},
        multitenancy: nil
      }

      remove_attribute = %Operation.RemoveAttribute{
        table: "posts",
        schema: nil,
        attribute: %{source: :title}
      }

      [fact] =
        OperationDeps.provides(remove_constraint)
        |> Enum.filter(&match?({:column_check_constraint_removed, _}, &1))

      assert fact in OperationDeps.requires(remove_attribute)
    end
  end

  describe "custom_statements" do
    test "AddCustomStatement's own-table requirement is satisfied by a CreateTable for that same table" do
      create = %Operation.CreateTable{table: "widget", schema: nil}

      statement = %Operation.AddCustomStatement{
        table: "widget",
        schema: nil,
        statement: %{name: :some_statement, up: "", down: "", code?: false}
      }

      [fact] =
        OperationDeps.provides(create) |> Enum.filter(&match?({:table_structure_ready, _}, &1))

      assert fact in OperationDeps.requires(statement)
    end
  end

  describe "early tier" do
    test "DropTable, RemoveCustomStatement, and the down-direction deferrability op are early tier" do
      assert OperationDeps.early_tier?(%Operation.DropTable{table: "posts", schema: nil})

      assert OperationDeps.early_tier?(%Operation.RemoveCustomStatement{
               table: "posts",
               statement: %{name: :x, up: "", down: "", code?: false}
             })

      assert OperationDeps.early_tier?(%Operation.AlterDeferrability{
               table: "posts",
               schema: nil,
               references: %{},
               direction: :down
             })

      refute OperationDeps.early_tier?(%Operation.AlterDeferrability{
               table: "posts",
               schema: nil,
               references: %{},
               direction: :up
             })
    end

    test "RemovePrimaryKey and AddPrimaryKeyDown are early tier; RemovePrimaryKeyDown and AddPrimaryKey are not" do
      assert OperationDeps.early_tier?(%Operation.RemovePrimaryKey{table: "posts", schema: nil})

      assert OperationDeps.early_tier?(%Operation.AddPrimaryKeyDown{
               table: "posts",
               schema: nil,
               keys: [:id],
               remove_old?: false
             })

      refute OperationDeps.early_tier?(%Operation.RemovePrimaryKeyDown{
               table: "posts",
               schema: nil
             })

      refute OperationDeps.early_tier?(%Operation.AddPrimaryKey{
               table: "posts",
               schema: nil,
               keys: [:id]
             })
    end

    test "RemovePrimaryKey requires column_fk_dropped for each of its own PK columns, satisfied only by a DropForeignKey{direction: :up} targeting that exact column" do
      remove_pk = %Operation.RemovePrimaryKey{table: "posts", schema: nil, keys: [:id]}

      # "comments" owns the FK column, but it targets "posts.id" — the fact
      # is scoped by the *referenced* table+column (Postgres blocks dropping
      # a PK while another table's FK still points at it), not the table
      # owning the FK.
      drop_fk_targeting_posts_id = %Operation.DropForeignKey{
        table: "comments",
        schema: nil,
        attribute: %{references: %{table: "posts", destination_attribute: :id, schema: nil}},
        direction: :up
      }

      drop_fk_targeting_other_column = %Operation.DropForeignKey{
        table: "comments",
        schema: nil,
        attribute: %{references: %{table: "posts", destination_attribute: :slug, schema: nil}},
        direction: :up
      }

      [fact] =
        OperationDeps.provides(drop_fk_targeting_posts_id)
        |> Enum.filter(&match?({:column_fk_dropped, _}, &1))

      assert fact in OperationDeps.requires(remove_pk)

      refute Enum.any?(
               OperationDeps.provides(drop_fk_targeting_other_column),
               &(&1 == fact)
             )
    end

    test "RemoveUniqueIndex requires column_fk_dropped for its own columns too (not just RemovePrimaryKey)" do
      # Regression: Postgres refuses to drop *any* unique constraint/index
      # still referenced by another table's foreign key, not just a primary
      # key (verified directly against Postgres) — a `belongs_to` with
      # `destination_attribute` can target a non-PK unique identity via
      # plain Ash DSL, so this is a reachable real scenario, not just a
      # custom_statements edge case.
      remove_index = %Operation.RemoveUniqueIndex{
        table: "parents",
        schema: nil,
        identity: %{keys: [:code]}
      }

      drop_fk_targeting_code = %Operation.DropForeignKey{
        table: "children",
        schema: nil,
        attribute: %{references: %{table: "parents", destination_attribute: :code, schema: nil}},
        direction: :up
      }

      [fact] =
        OperationDeps.provides(drop_fk_targeting_code)
        |> Enum.filter(&match?({:column_fk_dropped, _}, &1))

      assert fact in OperationDeps.requires(remove_index)
    end
  end
end
