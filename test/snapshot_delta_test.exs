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

      assert [%Operation.CreateTable{has_create_action: true, base_filter: nil}] =
               decoded.operations
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
      statement = %{
        name: :enable_trgm,
        up: "create extension pg_trgm",
        down: "drop extension pg_trgm"
      }

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

  # =================================================================
  # Reduction sequence coverage — exhaustive add/alter/remove/rename
  # cycles per op family, plus the cross-family conflict cases.
  # =================================================================

  describe "attribute reduction sequences" do
    setup do
      snapshot = %{
        table: "authors",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      %{
        snapshot: snapshot,
        empty: Reducer.empty_state(snapshot)
      }
    end

    defp throw_reason(fun) do
      fun.()
      :no_error
    catch
      :throw, {:reducer_error, reason} -> {:threw, reason}
    end

    defp add_attr(state, attr) do
      Reducer.apply_op(state, %Operation.AddAttribute{
        table: state.table,
        schema: state.schema,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        attribute: attr
      })
    end

    defp remove_attr(state, attr) do
      Reducer.apply_op(state, %Operation.RemoveAttribute{
        table: state.table,
        schema: state.schema,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        attribute: attr
      })
    end

    defp alter_attr(state, old_attr, new_attr) do
      Reducer.apply_op(state, %Operation.AlterAttribute{
        table: state.table,
        schema: state.schema,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        old_attribute: old_attr,
        new_attribute: new_attr
      })
    end

    defp rename_attr(state, old_attr, new_attr) do
      Reducer.apply_op(state, %Operation.RenameAttribute{
        table: state.table,
        schema: state.schema,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        old_attribute: old_attr,
        new_attribute: new_attr
      })
    end

    test "Add → Alter → Remove full lifecycle leaves attributes empty", %{empty: empty} do
      altered = %{@text_attribute | allow_nil?: false, default: "''"}

      state =
        empty
        |> add_attr(@text_attribute)
        |> alter_attr(@text_attribute, altered)

      assert [%{source: :email, allow_nil?: false, default: "''"}] = state.attributes

      state = remove_attr(state, altered)
      assert state.attributes == []
    end

    test "Add → Rename → Remove (by new name) succeeds", %{empty: empty} do
      renamed = %{@text_attribute | source: :primary_email}

      state =
        empty
        |> add_attr(@text_attribute)
        |> rename_attr(@text_attribute, renamed)

      assert [%{source: :primary_email}] = state.attributes

      state = remove_attr(state, renamed)
      assert state.attributes == []
    end

    test "Add → Rename → Rename again (chained renames) follows the new identity",
         %{empty: empty} do
      r1 = %{@text_attribute | source: :primary_email}
      r2 = %{r1 | source: :contact_email}

      state =
        empty
        |> add_attr(@text_attribute)
        |> rename_attr(@text_attribute, r1)
        |> rename_attr(r1, r2)

      assert [%{source: :contact_email}] = state.attributes
    end

    test "AlterAttribute on missing source raises conflict", %{empty: empty} do
      altered = %{@text_attribute | allow_nil?: false}

      assert {:threw, "AlterAttribute: attribute :email not present"} =
               throw_reason(fn -> alter_attr(empty, @text_attribute, altered) end)
    end

    test "RenameAttribute where destination matches source (no-op rename) is allowed",
         %{empty: empty} do
      # When old.source == new.source the rename is logically a metadata
      # update — should not trigger the destination-collision check.
      state = add_attr(empty, @text_attribute)
      altered = %{@text_attribute | allow_nil?: false}

      state = rename_attr(state, @text_attribute, altered)
      assert [%{source: :email, allow_nil?: false}] = state.attributes
    end

    test "Remove → Add at the same source is allowed (re-add cycle)", %{empty: empty} do
      state =
        empty
        |> add_attr(@text_attribute)
        |> remove_attr(@text_attribute)
        |> add_attr(%{@text_attribute | type: :string})

      assert [%{source: :email, type: :string}] = state.attributes
    end
  end

  describe "identity / unique index reduction sequences" do
    setup do
      snapshot = %{
        table: "authors",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      %{empty: Reducer.empty_state(snapshot)}
    end

    defp add_unique_index(state, identity) do
      Reducer.apply_op(state, %Operation.AddUniqueIndex{
        identity: identity,
        table: state.table,
        schema: state.schema,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy,
        concurrently: false
      })
    end

    defp remove_unique_index(state, identity) do
      Reducer.apply_op(state, %Operation.RemoveUniqueIndex{
        identity: identity,
        table: state.table,
        schema: state.schema,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy
      })
    end

    defp rename_unique_index(state, old_id, new_id) do
      Reducer.apply_op(state, %Operation.RenameUniqueIndex{
        old_identity: old_id,
        new_identity: new_id,
        table: state.table,
        schema: state.schema,
        multitenancy: @base_multitenancy,
        old_multitenancy: @base_multitenancy
      })
    end

    test "Add → Remove leaves identities empty", %{empty: empty} do
      state =
        empty
        |> add_unique_index(@base_identity)
        |> remove_unique_index(@base_identity)

      assert state.identities == []
    end

    test "Add same identity twice raises conflict", %{empty: empty} do
      state = add_unique_index(empty, @base_identity)

      assert {:threw, reason} =
               throw_reason(fn -> add_unique_index(state, @base_identity) end)

      assert reason =~ "AddUniqueIndex"
      assert reason =~ "unique_email"
    end

    test "Remove non-existent identity raises conflict", %{empty: empty} do
      assert {:threw, reason} =
               throw_reason(fn -> remove_unique_index(empty, @base_identity) end)

      assert reason =~ "RemoveUniqueIndex"
      assert reason =~ "unique_email"
    end

    test "Add → Rename to a different name succeeds and updates state", %{empty: empty} do
      renamed = %{@base_identity | name: :unique_primary_email}

      state =
        empty
        |> add_unique_index(@base_identity)
        |> rename_unique_index(@base_identity, renamed)

      assert [%{name: :unique_primary_email}] = state.identities
    end

    test "Rename non-existent identity raises conflict", %{empty: empty} do
      assert {:threw, _} =
               throw_reason(fn ->
                 rename_unique_index(empty, @base_identity, %{
                   @base_identity
                   | name: :other
                 })
               end)
    end
  end

  describe "check constraint reduction sequences" do
    setup do
      snapshot = %{
        table: "invoices",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      %{
        empty: Reducer.empty_state(snapshot),
        constraint: %{name: "positive_amount", check: "amount > 0", attribute: [:amount]}
      }
    end

    test "Add → Remove leaves check_constraints empty", %{empty: empty, constraint: c} do
      state =
        empty
        |> Reducer.apply_op(%Operation.AddCheckConstraint{
          table: empty.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          constraint: c
        })
        |> Reducer.apply_op(%Operation.RemoveCheckConstraint{
          table: empty.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          constraint: c
        })

      assert state.check_constraints == []
    end

    test "Add same constraint twice raises conflict", %{empty: empty, constraint: c} do
      state =
        Reducer.apply_op(empty, %Operation.AddCheckConstraint{
          table: empty.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          constraint: c
        })

      assert {:threw, reason} =
               throw_reason(fn ->
                 Reducer.apply_op(state, %Operation.AddCheckConstraint{
                   table: empty.table,
                   schema: nil,
                   multitenancy: @base_multitenancy,
                   old_multitenancy: @base_multitenancy,
                   constraint: c
                 })
               end)

      assert reason =~ "AddCheckConstraint"
    end

    test "Remove non-existent constraint raises conflict", %{empty: empty, constraint: c} do
      assert {:threw, reason} =
               throw_reason(fn ->
                 Reducer.apply_op(empty, %Operation.RemoveCheckConstraint{
                   table: empty.table,
                   schema: nil,
                   multitenancy: @base_multitenancy,
                   old_multitenancy: @base_multitenancy,
                   constraint: c
                 })
               end)

      assert reason =~ "RemoveCheckConstraint"
    end
  end

  describe "custom index reduction sequences" do
    setup do
      snapshot = %{
        table: "products",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      idx = %{
        name: "products_title_idx",
        fields: [:title],
        include: [],
        nulls_distinct: true,
        message: nil,
        all_tenants?: false
      }

      %{empty: Reducer.empty_state(snapshot), index: idx}
    end

    test "Add → Remove cycles cleanly", %{empty: empty, index: idx} do
      state =
        empty
        |> Reducer.apply_op(%Operation.AddCustomIndex{
          table: empty.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          index: idx
        })
        |> Reducer.apply_op(%Operation.RemoveCustomIndex{
          table: empty.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          index: idx
        })

      assert state.custom_indexes == []
    end

    test "Add same custom index twice raises conflict", %{empty: empty, index: idx} do
      state =
        Reducer.apply_op(empty, %Operation.AddCustomIndex{
          table: empty.table,
          schema: nil,
          multitenancy: @base_multitenancy,
          index: idx
        })

      assert {:threw, _} =
               throw_reason(fn ->
                 Reducer.apply_op(state, %Operation.AddCustomIndex{
                   table: empty.table,
                   schema: nil,
                   multitenancy: @base_multitenancy,
                   index: idx
                 })
               end)
    end
  end

  describe "table-level reduction sequences" do
    setup do
      snapshot = %{
        table: "things",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      create = fn ->
        %Operation.CreateTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: nil
        }
      end

      %{empty: Reducer.empty_state(snapshot), create: create}
    end

    test "CreateTable → DropTable resets to empty state", %{empty: empty, create: create} do
      state =
        empty
        |> Reducer.apply_op(create.())
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })

      assert [_] = state.attributes
      refute state.empty?

      state =
        Reducer.apply_op(state, %Operation.DropTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo
        })

      assert state.attributes == []
      assert state.empty?
    end

    test "CreateTable → DropTable → CreateTable can rebuild after a drop",
         %{empty: empty, create: create} do
      state =
        empty
        |> Reducer.apply_op(create.())
        |> Reducer.apply_op(%Operation.DropTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo
        })
        |> Reducer.apply_op(create.())
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })

      assert [%{source: :email}] = state.attributes
      refute state.empty?
    end

    test "RenameTable updates state.table and rejects mismatched old_table",
         %{empty: empty, create: create} do
      state =
        empty
        |> Reducer.apply_op(create.())
        |> Reducer.apply_op(%Operation.RenameTable{
          old_table: "things",
          new_table: "things_v2",
          schema: nil,
          multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo
        })

      assert state.table == "things_v2"

      assert {:threw, reason} =
               throw_reason(fn ->
                 Reducer.apply_op(state, %Operation.RenameTable{
                   old_table: "wrong",
                   new_table: "another",
                   schema: nil,
                   multitenancy: @base_multitenancy,
                   repo: AshPostgres.TestRepo
                 })
               end)

      assert reason =~ "RenameTable expected old_table=\"wrong\""
    end

    test "OptOutDropTable sets the flag without otherwise mutating state",
         %{empty: empty, create: create} do
      state =
        empty
        |> Reducer.apply_op(create.())
        |> Reducer.apply_op(%Operation.AddAttribute{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        })

      refute state.drop_table_opted_out

      state =
        Reducer.apply_op(state, %Operation.OptOutDropTable{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy
        })

      assert state.drop_table_opted_out
      # Other state untouched
      assert [%{source: :email}] = state.attributes
    end
  end

  describe "previous_hash chain validation" do
    @moduletag :tmp_dir

    test "two deltas with matching previous→resulting hashes reduce cleanly",
         %{tmp_dir: tmp_dir} do
      snapshot = %{
        table: "chained",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder = Path.join([tmp_dir, "test_repo", "chained"])
      File.mkdir_p!(folder)

      ops1 = [
        %Operation.CreateTable{
          table: "chained",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: nil
        }
      ]

      ops2 = [
        %Operation.AddAttribute{
          table: "chained",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        }
      ]

      File.write!(
        Path.join(folder, "20260101000000.json"),
        Codec.encode_delta(ops1, %{previous_hash: nil, resulting_hash: "AAAA"})
      )

      File.write!(
        Path.join(folder, "20260101000001.json"),
        Codec.encode_delta(ops2, %{previous_hash: "AAAA", resulting_hash: "BBBB"})
      )

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}
      state = Reducer.load_reduced_state(snapshot, opts)
      assert [%{source: :email}] = state.attributes
    end

    test "previous_hash that doesn't match prior resulting_hash raises ConflictError",
         %{tmp_dir: tmp_dir} do
      snapshot = %{
        table: "broken",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder = Path.join([tmp_dir, "test_repo", "broken"])
      File.mkdir_p!(folder)

      ops1 = [
        %Operation.CreateTable{
          table: "broken",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: nil
        }
      ]

      ops2 = [
        %Operation.AddAttribute{
          table: "broken",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        }
      ]

      File.write!(
        Path.join(folder, "20260101000000.json"),
        Codec.encode_delta(ops1, %{previous_hash: nil, resulting_hash: "AAAA"})
      )

      # second delta claims previous_hash WRONG_HASH which doesn't match AAAA
      File.write!(
        Path.join(folder, "20260101000001.json"),
        Codec.encode_delta(ops2, %{previous_hash: "WRONG_HASH", resulting_hash: "BBBB"})
      )

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}

      assert_raise Reducer.ConflictError, ~r/previous_hash.*does not match/, fn ->
        Reducer.load_reduced_state(snapshot, opts)
      end
    end

    test "deltas without hash metadata still reduce — chain validation is opt-in",
         %{tmp_dir: tmp_dir} do
      snapshot = %{
        table: "no_hash",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder = Path.join([tmp_dir, "test_repo", "no_hash"])
      File.mkdir_p!(folder)

      ops = [
        %Operation.CreateTable{
          table: "no_hash",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          repo: AshPostgres.TestRepo,
          create_table_options: nil
        },
        %Operation.AddAttribute{
          table: "no_hash",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: @text_attribute
        }
      ]

      # Deltas with no hash metadata at all — both prev_hash and result_hash nil.
      File.write!(
        Path.join(folder, "20260101000000.json"),
        Codec.encode_delta(ops)
      )

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}
      state = Reducer.load_reduced_state(snapshot, opts)
      assert [%{source: :email}] = state.attributes
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

  # =================================================================
  # Long delta chain — proves the reducer's invariants hold under
  # arbitrary sequences of ops, not just the 1-3 deltas the integration
  # tests exercise. Uses a simple oscillating add/remove/add cycle to
  # produce 100+ ops and asserts the final state matches the expected
  # set of attributes.
  # =================================================================

  describe "long delta chain" do
    @moduletag :tmp_dir

    test "reducing 100+ ops via direct apply_op yields the expected final state" do
      snapshot = %{
        table: "long_chain",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      mk_attr = fn name ->
        %{
          source: name,
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
      end

      add = fn s, a ->
        Reducer.apply_op(s, %Operation.AddAttribute{
          table: "long_chain",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: a
        })
      end

      remove = fn s, a ->
        Reducer.apply_op(s, %Operation.RemoveAttribute{
          table: "long_chain",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          attribute: a
        })
      end

      alter = fn s, old, new ->
        Reducer.apply_op(s, %Operation.AlterAttribute{
          table: "long_chain",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_multitenancy: @base_multitenancy,
          old_attribute: old,
          new_attribute: new
        })
      end

      # Build up 50 attributes one by one, alter each one to flip allow_nil?,
      # remove half of them, then re-add them with a different default. That's
      # 50 + 50 + 25 + 25 = 150 ops total.
      state = Reducer.empty_state(snapshot)

      attrs = for i <- 1..50, do: mk_attr.(:"col_#{i}")

      state = Enum.reduce(attrs, state, fn a, s -> add.(s, a) end)
      assert length(state.attributes) == 50

      altered_attrs =
        Enum.map(attrs, fn a -> %{a | allow_nil?: false} end)

      state =
        Enum.reduce(Enum.zip(attrs, altered_attrs), state, fn {old, new}, s ->
          alter.(s, old, new)
        end)

      assert Enum.all?(state.attributes, &(&1.allow_nil? == false))

      to_remove = Enum.take_every(altered_attrs, 2)

      state = Enum.reduce(to_remove, state, fn a, s -> remove.(s, a) end)
      assert length(state.attributes) == 25

      readded =
        Enum.map(to_remove, fn a -> %{a | default: "''"} end)

      state = Enum.reduce(readded, state, fn a, s -> add.(s, a) end)
      assert length(state.attributes) == 50

      # Final state: all 50 columns present. The 25 re-added ones retain
      # allow_nil? = false (carried over from the altered attribute they
      # were constructed from) and have default "''". The 25 untouched
      # ones also have allow_nil? = false from the original alter.
      readded_sources = MapSet.new(readded, & &1.source)

      Enum.each(state.attributes, fn attr ->
        assert attr.allow_nil? == false

        if MapSet.member?(readded_sources, attr.source) do
          assert attr.default == "''"
        else
          assert attr.default == "nil"
        end
      end)
    end

    test "reducing 60 delta files from disk in timestamp order yields the same state",
         %{tmp_dir: tmp_dir} do
      # Fans out the long-chain test across the on-disk path that codegen
      # actually exercises: 60 separate JSON files, sorted by timestamp,
      # each a single-op delta. Catches any edge cases the file-loop
      # has that direct apply_op doesn't (sort order, file IO, hash
      # chain validation falls back to nil so this is fine).
      snapshot = %{
        table: "long_disk_chain",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder = Path.join([tmp_dir, "test_repo", "long_disk_chain"])
      File.mkdir_p!(folder)

      # CreateTable as the first delta. Subsequent deltas each add one column.
      File.write!(
        Path.join(folder, "20260101000000.json"),
        Codec.encode_delta([
          %Operation.CreateTable{
            table: "long_disk_chain",
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            repo: AshPostgres.TestRepo,
            create_table_options: nil
          }
        ])
      )

      for i <- 1..60 do
        # 14-digit timestamps: 20260101 (date) + 6-digit zero-padded seq.
        ts = "20260101" <> String.pad_leading("#{i}", 6, "0")

        attr = %{
          source: :"col_#{i}",
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

        File.write!(
          Path.join(folder, "#{ts}.json"),
          Codec.encode_delta([
            %Operation.AddAttribute{
              table: "long_disk_chain",
              schema: nil,
              multitenancy: @base_multitenancy,
              old_multitenancy: @base_multitenancy,
              attribute: attr
            }
          ])
        )
      end

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}
      state = Reducer.load_reduced_state(snapshot, opts)

      assert length(state.attributes) == 60

      # Order: insertion order matters for downstream migration emission.
      # Reducer preserves insertion order via state.attributes ++ [attr].
      sources = Enum.map(state.attributes, & &1.source)
      expected = for i <- 1..60, do: :"col_#{i}"
      assert sources == expected
    end
  end

  # =================================================================
  # Robustness: hash stability + filename ordering. Cheap unit tests
  # for two failure modes that would silently corrupt state if they
  # ever broke.
  # =================================================================

  describe "robustness" do
    @moduletag :tmp_dir

    test "encoding the same op list with different map key orders produces the same JSON" do
      # The reducer uses `to_ordered_object/1` to sort keys before encoding.
      # If that ever regressed, two runs of the generator producing
      # logically-identical state could write different bytes — and
      # downstream tooling (migrate / squash / hash chain) would silently
      # diverge.
      mt = %{strategy: nil, attribute: nil, global: nil}
      mt_reordered = %{global: nil, strategy: nil, attribute: nil}

      attr_a = %{
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

      # Same fields inserted in a different literal order.
      attr_b = %{
        references: nil,
        generated?: false,
        allow_nil?: false,
        primary_key?: true,
        scale: nil,
        precision: nil,
        size: nil,
        default: "fragment(\"gen_random_uuid()\")",
        type: :uuid,
        source: :id
      }

      op_a = %Operation.AddAttribute{
        table: "things",
        schema: nil,
        multitenancy: mt,
        old_multitenancy: mt,
        attribute: attr_a
      }

      op_b = %Operation.AddAttribute{
        table: "things",
        schema: nil,
        multitenancy: mt_reordered,
        old_multitenancy: mt_reordered,
        attribute: attr_b
      }

      json_a = Codec.encode_delta([op_a], %{generated_at: "2026-01-01T00:00:00Z"})
      json_b = Codec.encode_delta([op_b], %{generated_at: "2026-01-01T00:00:00Z"})

      assert json_a == json_b,
             "encode_delta produced different bytes for logically-identical ops — to_ordered_object regressed"
    end

    test "reducer applies deltas in timestamp order regardless of write order",
         %{tmp_dir: tmp_dir} do
      # File systems (especially macOS HFS+, NTFS, network filesystems)
      # do NOT guarantee that File.ls! returns entries in any particular
      # order. The reducer relies on Enum.sort to canonicalize. This test
      # writes deltas in REVERSE timestamp order to verify the reducer
      # still applies them oldest→newest.
      snapshot = %{
        table: "out_of_order",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder = Path.join([tmp_dir, "test_repo", "out_of_order"])
      File.mkdir_p!(folder)

      ts1 = "20260101000000"
      ts2 = "20260101000001"
      ts3 = "20260101000002"

      # Write in REVERSE order — the file system may serve them this way.
      File.write!(
        Path.join(folder, "#{ts3}.json"),
        Codec.encode_delta([
          %Operation.AddAttribute{
            table: "out_of_order",
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            attribute: %{@text_attribute | source: :third}
          }
        ])
      )

      File.write!(
        Path.join(folder, "#{ts2}.json"),
        Codec.encode_delta([
          %Operation.AddAttribute{
            table: "out_of_order",
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            attribute: %{@text_attribute | source: :second}
          }
        ])
      )

      File.write!(
        Path.join(folder, "#{ts1}.json"),
        Codec.encode_delta([
          %Operation.CreateTable{
            table: "out_of_order",
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            repo: AshPostgres.TestRepo,
            create_table_options: nil
          }
        ])
      )

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}
      state = Reducer.load_reduced_state(snapshot, opts)

      # Insertion order on state.attributes reflects the order ops were applied.
      # If sorting regressed, we'd see the AddAttribute applied BEFORE
      # CreateTable, causing some other state corruption — but the
      # reducer's CreateTable apply is intentionally lenient about
      # collection state, so we check that all three attributes ended up
      # present in the right SEQUENCE.
      sources = Enum.map(state.attributes, & &1.source)

      assert sources == [:second, :third],
             "Reducer applied deltas out of timestamp order. Got #{inspect(sources)}"
    end

    test "reducer ignores non-delta files in the snapshot directory", %{tmp_dir: tmp_dir} do
      # Generators or VCS tools can drop garbage into the directory
      # (.gitkeep, .DS_Store, README.md, backup files). The reducer must
      # only consider strict NNNNNNNNNNNNNN.json filenames.
      snapshot = %{
        table: "with_garbage",
        schema: nil,
        repo: AshPostgres.TestRepo,
        multitenancy: @base_multitenancy
      }

      folder = Path.join([tmp_dir, "test_repo", "with_garbage"])
      File.mkdir_p!(folder)

      # Real delta.
      File.write!(
        Path.join(folder, "20260101000000.json"),
        Codec.encode_delta([
          %Operation.CreateTable{
            table: "with_garbage",
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            repo: AshPostgres.TestRepo,
            create_table_options: nil
          },
          %Operation.AddAttribute{
            table: "with_garbage",
            schema: nil,
            multitenancy: @base_multitenancy,
            old_multitenancy: @base_multitenancy,
            attribute: @text_attribute
          }
        ])
      )

      # Non-delta files that would explode if the reducer tried to read them.
      File.write!(Path.join(folder, ".DS_Store"), <<0, 0, 0, 1, 0, 0>>)
      File.write!(Path.join(folder, "README.md"), "# notes")
      File.write!(Path.join(folder, "backup.json.bak"), "{}")
      File.write!(Path.join(folder, "20260101.json"), "not a 14-digit timestamp")

      opts = %AshPostgres.MigrationGenerator{snapshot_path: tmp_dir, dev: false, quiet: true}
      state = Reducer.load_reduced_state(snapshot, opts)

      assert [%{source: :email}] = state.attributes
    end
  end
end
