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

    test "pseudo-ops (SetBaseFilter, OptOutDropTable) round-trip" do
      ops = [
        %Operation.SetBaseFilter{
          table: "things",
          schema: nil,
          multitenancy: @base_multitenancy,
          old_value: nil,
          new_value: "deleted_at IS NULL"
        },
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

      assert [
               %Operation.SetBaseFilter{new_value: "deleted_at IS NULL"},
               %Operation.OptOutDropTable{}
             ] =
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
end
