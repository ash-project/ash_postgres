# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.SnapshotDeltaTest do
  use ExUnit.Case, async: true

  alias AshPostgres.MigrationGenerator.Operation
  alias AshPostgres.MigrationGenerator.Operation.Codec
  alias AshPostgres.MigrationGenerator.Reducer
  alias AshPostgres.MigrationGenerator.Reducer.LegacyFormatError

  @base_attribute %{
    source: :id,
    type: :uuid,
    default: "fragment(\"gen_random_uuid()\")",
    size: nil,
    precision: nil,
    scale: nil,
    primary_key?: true,
    allow_nil?: false,
    generated?: false,
    references: nil
  }

  @text_attribute %{
    source: :email,
    type: :text,
    default: "nil",
    size: nil,
    precision: nil,
    scale: nil,
    primary_key?: false,
    allow_nil?: true,
    generated?: false,
    references: nil
  }

  @base_identity %{
    name: :unique_email,
    keys: [:email],
    index_name: "authors_unique_email_index",
    base_filter: nil,
    where: nil,
    all_tenants?: false,
    nils_distinct?: true
  }

  @base_multitenancy %{strategy: nil, attribute: nil, global: nil}

  describe "codec delta round-trip" do
    test "simple AddAttribute round-trips" do
      op = %Operation.AddAttribute{
        table: "authors",
        schema: nil,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        attribute: @text_attribute
      }

      json = Codec.encode_delta([op])
      assert Codec.delta?(json)

      decoded = Codec.decode_delta(json)
      assert [decoded_op] = decoded.operations
      assert %Operation.AddAttribute{} = decoded_op
      assert decoded_op.table == "authors"
      assert decoded_op.attribute.source == :email
      assert decoded_op.attribute.type == :text
    end

    test "CreateTable + AddAttribute round-trip" do
      ops = [
        %Operation.CreateTable{
          table: "authors",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: nil
        },
        %Operation.AddAttribute{
          table: "authors",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @base_attribute
        }
      ]

      json = Codec.encode_delta(ops)
      decoded = Codec.decode_delta(json)

      assert [%Operation.CreateTable{} = create, %Operation.AddAttribute{} = add] =
               decoded.operations

      assert create.repo == AshPostgres.TestRepo
      assert add.attribute.source == :id
      assert add.attribute.primary_key? == true
    end

    test "AddUniqueIndex with mixed atom/string keys round-trips" do
      identity =
        Map.merge(@base_identity, %{
          keys: [:name, "custom_expr"],
          index_name: "things_name_unique_index"
        })

      op = %Operation.AddUniqueIndex{
        identity: identity,
        table: "things",
        schema: nil,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        concurrently: false
      }

      decoded =
        [op]
        |> Codec.encode_delta()
        |> Codec.decode_delta()

      assert [%Operation.AddUniqueIndex{identity: id}] = decoded.operations
      assert id.keys == [:name, "custom_expr"]
    end

    test "AddAttribute with references + nilify on_delete round-trips" do
      attr_with_ref = %{
        @text_attribute
        | source: :post_id,
          type: :uuid,
          references: %{
            destination_attribute: :id,
            destination_attribute_default: "nil",
            destination_attribute_generated: false,
            table: "posts",
            schema: nil,
            multitenancy: @base_multitenancy,
            on_delete: {:nilify, [:post_id]},
            on_update: :update,
            deferrable: false,
            index?: false,
            match_with: nil,
            match_type: nil,
            name: "comments_post_id_fkey"
          }
      }

      op = %Operation.AddAttribute{
        table: "comments",
        schema: nil,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        attribute: attr_with_ref
      }

      decoded =
        [op]
        |> Codec.encode_delta()
        |> Codec.decode_delta()

      assert [%Operation.AddAttribute{attribute: a}] = decoded.operations
      assert a.references.on_delete == {:nilify, [:post_id]}
      assert a.references.on_update == :update
    end

    test "rejects non-v2 JSON with an informative error" do
      legacy_json = ~s({"attributes": [], "table": "foo"})

      assert_raise ArgumentError, ~r/Expected delta snapshot version 2/, fn ->
        Codec.decode_delta(legacy_json)
      end

      refute Codec.delta?(legacy_json)
    end

    test "rejects malformed JSON with a parseable error message" do
      assert_raise ArgumentError, ~r/Could not parse delta snapshot JSON/, fn ->
        Codec.decode_delta("not valid json {[")
      end

      refute Codec.delta?("not valid json {[")
    end

    test "rejects JSON that isn't a top-level object" do
      assert_raise ArgumentError, ~r/Expected delta snapshot to be a JSON object/, fn ->
        Codec.decode_delta("[1, 2, 3]")
      end

      assert_raise ArgumentError, ~r/Expected delta snapshot to be a JSON object/, fn ->
        Codec.decode_delta("\"a string\"")
      end
    end

    test "OptOutDropTable round-trips" do
      ops = [
        %Operation.OptOutDropTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy
        }
      ]

      decoded =
        ops
        |> Codec.encode_delta()
        |> Codec.decode_delta()

      assert [%Operation.OptOutDropTable{}] = decoded.operations
    end

    test "CreateTable carries base_filter and has_create_action through round-trip" do
      op = %Operation.CreateTable{
        table: "things",
        schema: nil,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        repo: AshPostgres.TestRepo,
        create_table_options: "WITH (fillfactor=70)",
        base_filter: "deleted_at IS NULL",
        has_create_action: false
      }

      decoded =
        [op]
        |> Codec.encode_delta()
        |> Codec.decode_delta()

      assert [
               %Operation.CreateTable{
                 base_filter: "deleted_at IS NULL",
                 has_create_action: false,
                 create_table_options: "WITH (fillfactor=70)"
               }
             ] = decoded.operations
    end

    test "CreateTable.has_create_action defaults to true when absent from a decoded op" do
      # Forward-compat: if a delta written before has_create_action was added
      # is decoded, we default to Ash's historical true so downstream doesn't
      # see nil-vs-false ambiguity.
      json =
        Jason.encode!(%{
          version: 2,
          operations: [
            %{
              type: "create_table",
              table: "legacy",
              schema: nil,
              multitenancy: Codec.encode_multitenancy(@base_multitenancy),
              old_multitenancy: Codec.encode_multitenancy(@base_multitenancy),
              repo: "Elixir.AshPostgres.TestRepo",
              create_table_options: nil
              # base_filter and has_create_action intentionally absent
            }
          ]
        })

      decoded = Codec.decode_delta(json)
      assert [%Operation.CreateTable{has_create_action: true, base_filter: nil}] = decoded.operations
    end
  end

  describe "reducer" do
    setup do
      snapshot = %{
        table: "authors",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      %{snapshot: snapshot}
    end

    test "empty state + CreateTable + AddAttribute produces populated state", %{
      snapshot: snapshot
    } do
      state = Reducer.empty_state(snapshot)

      state =
        Reducer.apply_op(state, %Operation.CreateTable{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: snapshot.repo,
          create_table_options: nil
        })

      state =
        Reducer.apply_op(state, %Operation.AddAttribute{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @base_attribute
        })

      assert state.empty? == false
      assert [%{source: :id}] = state.attributes
    end

    test "AddAttribute on existing source raises ConflictError", %{snapshot: snapshot} do
      state =
        snapshot
        |> Reducer.empty_state()
        |> Reducer.apply_op(%Operation.CreateTable{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: snapshot.repo
        })
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })

      assert_raise(RuntimeError, ~r/reducer_error/, fn ->
        # The reducer wraps apply_op errors in ConflictError via apply_file,
        # but apply_op/2 itself throws — catch that here.
        try do
          Reducer.apply_op(state, %Operation.AddAttribute{
            table: snapshot.table,
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            attribute: @text_attribute
          })
        catch
          :throw, {:reducer_error, reason} ->
            raise "reducer_error: #{reason}"
        end
      end)
    end

    test "RemoveAttribute on missing source is a conflict", %{snapshot: snapshot} do
      state = Reducer.empty_state(snapshot)

      caught =
        try do
          Reducer.apply_op(state, %Operation.RemoveAttribute{
            table: snapshot.table,
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            attribute: @text_attribute
          })

          :no_error
        catch
          :throw, {:reducer_error, reason} -> {:threw, reason}
        end

      assert {:threw, "RemoveAttribute: attribute :email not present"} = caught
    end

    test "RenameAttribute: missing source is reported BEFORE existing destination",
         %{snapshot: snapshot} do
      # Regression test for post-refactor check ordering. Before the helper
      # collapse, the reducer checked "source present" first and "destination
      # free" second. If both were violated (source missing + destination
      # present), the old message was "source :x not present". Make sure the
      # refactor didn't flip the order.
      state =
        snapshot
        |> Reducer.empty_state()
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })

      caught =
        try do
          # Destination (:email) exists, source (:nonexistent_src) doesn't.
          Reducer.apply_op(state, %Operation.RenameAttribute{
            table: snapshot.table,
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            old_attribute: %{@text_attribute | source: :nonexistent_src},
            new_attribute: @text_attribute
          })

          :no_error
        catch
          :throw, {:reducer_error, reason} -> {:threw, reason}
        end

      assert {:threw, "RenameAttribute: source :nonexistent_src not present"} = caught
    end

    test "RenameAttribute: existing destination throws after source-found check",
         %{snapshot: snapshot} do
      # Separate clause: source exists, but destination collision.
      other_attr = %{@text_attribute | source: :other_col}

      state =
        snapshot
        |> Reducer.empty_state()
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: other_attr
        })

      caught =
        try do
          Reducer.apply_op(state, %Operation.RenameAttribute{
            table: snapshot.table,
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            old_attribute: @text_attribute,
            new_attribute: other_attr
          })

          :no_error
        catch
          :throw, {:reducer_error, reason} -> {:threw, reason}
        end

      assert {:threw, "RenameAttribute: destination :other_col already exists"} = caught
    end

    test "AddCustomStatement / RemoveCustomStatement round-trip through apply_op",
         %{snapshot: snapshot} do
      # Apply_op path for these ops wasn't previously exercised by a unit
      # test. Covering the helper-based add/remove plumbing explicitly.
      statement = %{name: :enable_trgm, up: "create extension pg_trgm", down: "drop extension pg_trgm"}

      state =
        snapshot
        |> Reducer.empty_state()
        |> Reducer.apply_op(%Operation.AddCustomStatement{
          table: snapshot.table,
          statement: statement
        })

      assert state.empty? == false
      assert [^statement] = state.custom_statements

      state =
        Reducer.apply_op(state, %Operation.RemoveCustomStatement{
          table: snapshot.table,
          statement: statement
        })

      assert state.custom_statements == []

      # Remove again should conflict
      caught =
        try do
          Reducer.apply_op(state, %Operation.RemoveCustomStatement{
            table: snapshot.table,
            statement: statement
          })

          :no_error
        catch
          :throw, {:reducer_error, reason} -> {:threw, reason}
        end

      assert {:threw, "RemoveCustomStatement: statement :enable_trgm not present"} = caught
    end

    test "state.empty? after add-then-remove-all reflects 'state was touched', not 'state is empty now'",
         %{snapshot: snapshot} do
      # Intentional post-simplification behavior: dropping the final
      # state_empty?/1 recomputation means `empty?` tracks "has any op been
      # applied" (inline per apply_op), not "are all collections empty right
      # now". For `pkey_operations`' purpose — deciding whether to skip pkey
      # drops because we're a fresh create — this is more correct: removing
      # attributes from an existing table is NOT a fresh-create scenario, so
      # we must keep `empty?=false`.
      state =
        snapshot
        |> Reducer.empty_state()
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })
        |> Reducer.apply_op(%Operation.RemoveAttribute{
          table: snapshot.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })

      assert state.attributes == []
      refute state.empty?, "empty? must stay false once state has been touched by any op"
    end
  end

  describe "load_reduced_state" do
    @moduletag :tmp_dir

    test "returns nil for an empty directory", %{tmp_dir: tmp_dir} do
      snapshot = %{
        table: "missing",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}

      assert Reducer.load_reduced_state(snapshot, opts) == nil
    end

    test "rejects legacy full-state files with a clear error", %{tmp_dir: tmp_dir} do
      snapshot = %{
        table: "customers",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder =
        tmp_dir
        |> Path.join(
          AshPostgres.MigrationGenerator
          |> Module.split()
          |> Enum.at(0)
          |> then(fn _ -> "test_repo" end)
        )
        |> Path.join("customers")

      File.mkdir_p!(folder)

      legacy_content = ~s({"attributes": [], "table": "customers", "hash": "abc"})
      File.write!(Path.join(folder, "20260101000000.json"), legacy_content)

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}

      assert_raise LegacyFormatError, ~r/mix ash_postgres.migrate_snapshots/, fn ->
        Reducer.load_reduced_state(snapshot, opts)
      end
    end

    test "reduces a single delta to state", %{tmp_dir: tmp_dir} do
      snapshot = %{
        table: "authors",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder = Path.join([tmp_dir, "test_repo", "authors"])
      File.mkdir_p!(folder)

      ops = [
        %Operation.CreateTable{
          table: "authors",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: nil
        },
        %Operation.AddAttribute{
          table: "authors",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @base_attribute
        }
      ]

      File.write!(
        Path.join(folder, "20260101000000.json"),
        Codec.encode_delta(ops, %{previous_hash: nil, resulting_hash: "DEADBEEF"})
      )

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}

      state = Reducer.load_reduced_state(snapshot, opts)
      assert state.empty? == false
      assert [%{source: :id}] = state.attributes
    end
  end

  # =================================================================
  # Regression tests for known data-loss bugs in the Reducer + initial
  # ops path. These all currently fail — see the /review output.
  # =================================================================

  describe "create_table_options round-trip" do
    test "CreateTable#create_table_options encode + decode preserves value" do
      ops = [
        %Operation.CreateTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: "WITH (fillfactor=70)"
        }
      ]

      decoded =
        ops
        |> Codec.encode_delta()
        |> Codec.decode_delta()

      assert [%Operation.CreateTable{create_table_options: "WITH (fillfactor=70)"}] =
               decoded.operations
    end

    test "Reducer preserves create_table_options on CreateTable — squash round-trip" do
      # Simulate a legacy squash: reduce a delta chain to state, then ask the
      # generator for the initial delta for that state. `create_table_options`
      # must survive the trip, otherwise squash silently drops user-set
      # storage parameters like `WITH (fillfactor=70)`.
      ops = [
        %Operation.CreateTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: "WITH (fillfactor=70)"
        },
        %Operation.AddAttribute{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @base_attribute
        }
      ]

      snapshot = %{
        table: "things",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      state =
        Enum.reduce(ops, Reducer.empty_state(snapshot), fn op, s ->
          Reducer.apply_op(s, op)
        end)

      # Reduced state must carry create_table_options for squash to re-emit it.
      assert state.create_table_options == "WITH (fillfactor=70)"

      regenerated =
        AshPostgres.MigrationGenerator.initial_operations_for_state(state)

      create =
        Enum.find(regenerated, &match?(%Operation.CreateTable{}, &1))

      assert create != nil, "initial_operations_for_state emitted no CreateTable"

      assert create.create_table_options == "WITH (fillfactor=70)",
             "create_table_options dropped by squash — got #{inspect(create.create_table_options)}"
    end

    test "CreateTable hydrates base_filter and has_create_action on the reduced state" do
      # After the pseudo-op collapse, these scalars are carried on CreateTable
      # itself. Reducing a delta that starts with CreateTable must propagate
      # them into state so downstream consumers (e.g. identity regen via
      # `changing_multitenancy_affects_identities?`) see the correct old value.
      snapshot = %{
        table: "things",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      state =
        snapshot
        |> Reducer.empty_state()
        |> Reducer.apply_op(%Operation.CreateTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: "WITH (fillfactor=70)",
          base_filter: "deleted_at IS NULL",
          has_create_action: false
        })

      assert state.create_table_options == "WITH (fillfactor=70)"
      assert state.base_filter == "deleted_at IS NULL"
      assert state.has_create_action == false
    end
  end

  describe "state_empty? consistency" do
    test "CreateTable flips empty? to false even before any attribute ops", %{} do
      # Invariant: the Reducer treats any mutation of a scalar state field
      # (base_filter via CreateTable, has_create_action via CreateTable,
      # drop_table_opted_out via OptOutDropTable) as non-emptiness, not just
      # collection additions. Without this, `pkey_operations/4` would treat a
      # post-CreateTable state as if it were a fresh-create snapshot.
      snapshot = %{
        table: "things",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      state =
        snapshot
        |> Reducer.empty_state()
        |> Reducer.apply_op(%Operation.CreateTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: nil,
          base_filter: "deleted_at IS NULL",
          has_create_action: true
        })

      assert state.base_filter == "deleted_at IS NULL"
      refute state.empty?
    end
  end
end
