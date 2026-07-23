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
        |> Enum.filter(&match?({:unique_index_created, _}, &1))

      assert index_fact == {:unique_index_created, {"public", "posts", [:id]}}
      assert column_fact in requires
      assert index_fact in requires
    end

    test "a composite FK (match_with) requires a unique index covering exactly its referenced column set" do
      # e.g. `reference :dept, match_with: [org_id: :org_id]` produces a
      # composite FK on dept (id, org_id); Postgres requires one unique index
      # covering exactly those columns, which here is a custom index rather
      # than an identity (identities mix in base_filter, making the index
      # partial and unusable as an FK target).
      referenced_index = %Operation.AddCustomIndex{
        table: "dept",
        schema: nil,
        index: %{name: "dept_org_id_id_index", unique: true, fields: ["org_id", "id"]},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      referencing_attribute = %Operation.AddAttribute{
        table: "customer",
        schema: nil,
        attribute: %{
          source: :dept_id,
          primary_key?: false,
          references: %{
            table: "dept",
            destination_attribute: :id,
            schema: "public",
            match_with: %{org_id: :org_id}
          }
        }
      }

      requires = OperationDeps.requires(referencing_attribute)

      # provider side: string field names normalize into one sorted atom set
      [index_fact] =
        OperationDeps.provides(referenced_index)
        |> Enum.filter(&match?({:unique_index_created, _}, &1))

      assert index_fact == {:unique_index_created, {"public", "dept", [:id, :org_id]}}

      # consumer side: the FK waits for the covering index and the extra column
      assert index_fact in requires
      assert {:column_ready, {"public", "dept", :org_id}} in requires
    end

    test "a composite FK (match_with) also requires its own table's source columns (issue #805)" do
      # `reference :a, match_with: [site_id: :site_id]` on junctions makes
      # junctions.site_id part of the FK constraint, so the FK can't be
      # created before that sibling column exists. The attribute's own source
      # column is excluded — it's the column the operation itself adds.
      referencing_attribute = %Operation.AddAttribute{
        table: "junctions",
        schema: nil,
        attribute: %{
          source: :a_id,
          primary_key?: false,
          references: %{
            table: "as",
            destination_attribute: :id,
            schema: "public",
            match_with: %{site_id: :site_id}
          }
        }
      }

      source_column = %Operation.AddAttribute{
        table: "junctions",
        schema: nil,
        attribute: %{source: :site_id, primary_key?: true}
      }

      requires = OperationDeps.requires(referencing_attribute)

      [column_fact] =
        OperationDeps.provides(source_column) |> Enum.filter(&match?({:column_ready, _}, &1))

      assert column_fact == {:column_ready, {"public", "junctions", :site_id}}
      assert column_fact in requires
      refute {:column_ready, {"public", "junctions", :a_id}} in requires
    end

    test "a down-direction DropForeignKey waits for all of its table's column operations (issue #805)" do
      # DropForeignKey{direction: :down} renders nothing in `up`; it exists so
      # `down` drops the constraint its paired Add/AlterAttribute created.
      # Requiring `table_columns_settled` keeps it after that paired op and
      # out of the middle of a `create table`'s column operations, where it
      # would split the create phase (leaving e.g. a primary-key column to an
      # invalid later `alter`).
      drop_down = %Operation.DropForeignKey{
        table: "junctions",
        schema: nil,
        attribute: %{references: %{table: "as", destination_attribute: :id, schema: nil}},
        direction: :down
      }

      fk_alter = %Operation.AlterAttribute{
        table: "junctions",
        schema: nil,
        old_attribute: %{source: :a_id},
        new_attribute: %{
          source: :a_id,
          references: %{table: "as", destination_attribute: :id, schema: "public"}
        }
      }

      [settled_fact] =
        OperationDeps.provides(fk_alter)
        |> Enum.filter(&match?({:table_columns_settled, _}, &1))

      assert settled_fact in OperationDeps.requires(drop_down)

      # the up-direction op (used when dropping/replacing an FK) keeps its
      # narrower requirement so drop sequences are not disturbed
      refute settled_fact in OperationDeps.requires(%{drop_down | direction: :up})
    end

    test "separate single-column unique indexes do not satisfy a composite FK's covering-index requirement" do
      # Postgres requires ONE unique index on exactly (id, org_id); a unique
      # index on (id) plus another on (org_id) does not qualify, and
      # correspondingly neither provides the column-set fact the FK requires.
      id_index = %Operation.AddCustomIndex{
        table: "dept",
        schema: nil,
        index: %{name: nil, unique: true, fields: ["id"]},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      org_id_index = %Operation.AddCustomIndex{
        table: "dept",
        schema: nil,
        index: %{name: nil, unique: true, fields: ["org_id"]},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      referencing_attribute = %Operation.AddAttribute{
        table: "customer",
        schema: nil,
        attribute: %{
          source: :dept_id,
          primary_key?: false,
          references: %{
            table: "dept",
            destination_attribute: :id,
            schema: "public",
            match_with: %{org_id: :org_id}
          }
        }
      }

      [required_index_fact] =
        OperationDeps.requires(referencing_attribute)
        |> Enum.filter(&match?({:unique_index_created, _}, &1))

      refute required_index_fact in OperationDeps.provides(id_index)
      refute required_index_fact in OperationDeps.provides(org_id_index)
    end

    test "the provided column set includes the tenant attribute that multitenancy prefixes at render time" do
      # The rendered index is (org_id, secondary_id), not (secondary_id) —
      # see Operation.Helper.index_keys/3 — so the fact must say so, or a
      # composite FK targeting (org_id, secondary_id) would never link to it.
      op = %Operation.AddUniqueIndex{
        table: "users",
        schema: nil,
        identity: %{keys: [:secondary_id], where: nil, base_filter: nil},
        multitenancy: %{strategy: :attribute, attribute: :org_id, global: false}
      }

      assert {:unique_index_created, {"public", "users", [:org_id, :secondary_id]}} in OperationDeps.provides(
               op
             )
    end

    test "a non-unique custom index does not provide unique_index_created" do
      index_op = %Operation.AddCustomIndex{
        table: "dept",
        schema: nil,
        index: %{name: nil, unique: false, fields: ["org_id"]},
        base_filter: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      refute Enum.any?(
               OperationDeps.provides(index_op),
               &match?({:unique_index_created, _}, &1)
             )
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

    test "RemoveReferenceIndex and AddReferenceIndex on the same source column are linked" do
      # Both derive the same auto-generated index name from their columns, so
      # the add can't run while the old index still exists (e.g. an index_where
      # rewrite of an existing reference index).
      remove = %Operation.RemoveReferenceIndex{
        table: "posts",
        schema: nil,
        source: :author_id,
        multitenancy: %{attribute: nil, strategy: nil, global: nil},
        old_multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      add = %Operation.AddReferenceIndex{
        table: "posts",
        schema: nil,
        source: :author_id,
        where: "author_id IS NOT NULL",
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      [fact] =
        OperationDeps.provides(remove)
        |> Enum.filter(&match?({:reference_index_removed, _}, &1))

      assert fact in OperationDeps.requires(add)
    end

    test "AddReferenceIndex is NOT linked to a RemoveReferenceIndex on a different source column" do
      remove = %Operation.RemoveReferenceIndex{
        table: "posts",
        schema: nil,
        source: :editor_id,
        multitenancy: %{attribute: nil, strategy: nil, global: nil},
        old_multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      add = %Operation.AddReferenceIndex{
        table: "posts",
        schema: nil,
        source: :author_id,
        where: nil,
        multitenancy: %{attribute: nil, strategy: nil, global: nil}
      }

      [fact] =
        OperationDeps.provides(remove)
        |> Enum.filter(&match?({:reference_index_removed, _}, &1))

      refute fact in OperationDeps.requires(add)
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
    test "AddCustomStatement's own-table requirement is satisfied by a CreateTable for that same table (via table_structure_ready)" do
      create = %Operation.CreateTable{table: "widget", schema: nil}

      statement = %Operation.AddCustomStatement{
        table: "widget",
        schema: nil,
        statement: %{name: :some_statement, up: "", down: "", code?: false, after_tables: []}
      }

      [fact] =
        OperationDeps.provides(create) |> Enum.filter(&match?({:table_structure_ready, _}, &1))

      assert fact in OperationDeps.requires(statement)
    end

    test "AddCustomStatement with after_tables is satisfied by a CreateTable for the declared table (via table_finalized)" do
      create = %Operation.CreateTable{table: "parents", schema: nil}

      statement = %Operation.AddCustomStatement{
        table: "widget",
        schema: nil,
        statement: %{
          name: :widget_parent_composite_fk,
          up: "",
          down: "",
          code?: false,
          after_tables: ["parents"]
        }
      }

      [fact] = OperationDeps.provides(create) |> Enum.filter(&match?({:table_finalized, _}, &1))

      assert fact in OperationDeps.requires(statement)
    end

    test "AddCustomStatement with after_tables is satisfied by another custom statement declared on the target table" do
      # This is the whole point of the two-tier fact split: a shared,
      # foundational custom statement (e.g. one that creates a structure
      # another table's FK needs) can live on the table it actually concerns,
      # and other resources' `after_tables` will wait for it too — not just
      # for that table's plain structural (DDL) operations.
      parent_statement = %Operation.AddCustomStatement{
        table: "parents",
        schema: nil,
        statement: %{
          name: :parents_composite_unique_index,
          up: "",
          down: "",
          code?: false,
          after_tables: []
        }
      }

      child_statement = %Operation.AddCustomStatement{
        table: "widget",
        schema: nil,
        statement: %{
          name: :widget_parent_composite_fk,
          up: "",
          down: "",
          code?: false,
          after_tables: ["parents"]
        }
      }

      [fact] =
        OperationDeps.provides(parent_statement)
        |> Enum.filter(&match?({:table_finalized, _}, &1))

      assert fact in OperationDeps.requires(child_statement)
    end

    test "two custom statements declared on the same table do not require each other (no sibling cycle)" do
      statement_a = %Operation.AddCustomStatement{
        table: "widget",
        schema: nil,
        statement: %{name: :a, up: "", down: "", code?: false, after_tables: []}
      }

      statement_b = %Operation.AddCustomStatement{
        table: "widget",
        schema: nil,
        statement: %{name: :b, up: "", down: "", code?: false, after_tables: []}
      }

      # Each provides :table_finalized for their shared table (so *other*
      # tables' after_tables can depend on either of them), but neither's own
      # implicit requirement is written in terms of that same broad fact —
      # only the narrower :table_structure_ready, which neither custom
      # statement provides. If this ever regresses, `AddCustomStatement`s on
      # a shared table would deadlock (a real cycle) via each other's
      # `:table_finalized`.
      refute Enum.any?(
               OperationDeps.provides(statement_a),
               &match?({:table_structure_ready, _}, &1)
             )

      refute Enum.any?(
               OperationDeps.requires(statement_b),
               &match?({:table_finalized, _}, &1)
             )
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
