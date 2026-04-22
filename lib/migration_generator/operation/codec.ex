# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationGenerator.Operation.Codec do
  @moduledoc false

  alias AshPostgres.MigrationGenerator.Operation

  @delta_version 2

  @op_to_type %{
    Operation.CreateTable => "create_table",
    Operation.DropTable => "drop_table",
    Operation.RenameTable => "rename_table",
    Operation.AddAttribute => "add_attribute",
    Operation.AlterAttribute => "alter_attribute",
    Operation.RenameAttribute => "rename_attribute",
    Operation.RemoveAttribute => "remove_attribute",
    Operation.DropForeignKey => "drop_foreign_key",
    Operation.AlterDeferrability => "alter_deferrability",
    Operation.AddUniqueIndex => "add_unique_index",
    Operation.RemoveUniqueIndex => "remove_unique_index",
    Operation.RenameUniqueIndex => "rename_unique_index",
    Operation.AddCustomIndex => "add_custom_index",
    Operation.RemoveCustomIndex => "remove_custom_index",
    Operation.AddReferenceIndex => "add_reference_index",
    Operation.RemoveReferenceIndex => "remove_reference_index",
    Operation.AddPrimaryKey => "add_primary_key",
    Operation.AddPrimaryKeyDown => "add_primary_key_down",
    Operation.RemovePrimaryKey => "remove_primary_key",
    Operation.RemovePrimaryKeyDown => "remove_primary_key_down",
    Operation.AddCustomStatement => "add_custom_statement",
    Operation.RemoveCustomStatement => "remove_custom_statement",
    Operation.AddCheckConstraint => "add_check_constraint",
    Operation.RemoveCheckConstraint => "remove_check_constraint",
    Operation.SetBaseFilter => "set_base_filter",
    Operation.SetHasCreateAction => "set_has_create_action",
    Operation.SetCreateTableOptions => "set_create_table_options",
    Operation.OptOutDropTable => "opt_out_drop_table"
  }

  @type_to_op Map.new(@op_to_type, fn {k, v} -> {v, k} end)

  # =================================================================
  # Full-state codec (legacy format)
  # =================================================================

  @doc """
  Serialize a full-state snapshot map to a pretty-printed JSON string.

  Byte-identical output to the historical `snapshot_to_binary/1`.
  """
  def encode_full_state(snapshot) do
    snapshot
    |> Map.update!(:attributes, fn attributes ->
      Enum.map(attributes, &encode_attribute/1)
    end)
    |> Map.update!(:custom_indexes, fn indexes ->
      Enum.map(indexes, &encode_custom_index/1)
    end)
    |> Map.update!(:identities, fn identities ->
      Enum.map(identities, &encode_identity/1)
    end)
    |> to_ordered_object()
    |> Jason.encode!(pretty: true)
  end

  @doc "Decode a full-state snapshot JSON string back into a sanitized map."
  def decode_full_state(json) do
    json
    |> Jason.decode!(keys: :atoms!)
    |> sanitize_snapshot()
  end

  @doc """
  Normalize an already-decoded snapshot map: fill in defaults, coerce atoms,
  decode nested shapes.
  """
  def sanitize_snapshot(snapshot) do
    snapshot
    |> Map.put_new(:has_create_action, true)
    |> Map.put_new(:schema, nil)
    |> Map.update!(:identities, fn identities ->
      Enum.map(identities, &decode_identity(&1, snapshot.table))
    end)
    |> Map.update!(:attributes, fn attributes ->
      Enum.map(attributes, fn attribute ->
        attribute = decode_attribute(attribute, snapshot.table)

        if is_map(Map.get(attribute, :references)) do
          %{
            attribute
            | references: rewrite(attribute.references, :ignore, :ignore?)
          }
        else
          attribute
        end
      end)
    end)
    |> Map.put_new(:custom_indexes, [])
    |> Map.update!(:custom_indexes, &Enum.map(&1 || [], fn i -> decode_custom_index(i) end))
    |> Map.put_new(:custom_statements, [])
    |> Map.update!(
      :custom_statements,
      &Enum.map(&1 || [], fn s -> decode_custom_statement(s) end)
    )
    |> Map.put_new(:check_constraints, [])
    |> Map.update!(:check_constraints, &Enum.map(&1, fn c -> decode_check_constraint(c) end))
    |> Map.update!(:repo, &maybe_to_atom/1)
    |> Map.put_new(:multitenancy, %{attribute: nil, strategy: nil, global: nil})
    |> Map.update!(:multitenancy, &decode_multitenancy/1)
    |> Map.put_new(:base_filter, nil)
    |> Map.put_new(:drop_table_opted_out, false)
  end

  @doc """
  Recursively convert a value into a Jason.OrderedObject (stable key ordering
  for deterministic hashes).
  """
  def to_ordered_object(value) when is_map(value) do
    value
    |> Map.to_list()
    |> List.keysort(0)
    |> Enum.map(fn {key, value} -> {key, to_ordered_object(value)} end)
    |> Jason.OrderedObject.new()
  end

  def to_ordered_object(value) when is_list(value), do: Enum.map(value, &to_ordered_object/1)
  def to_ordered_object(value), do: value

  # =================================================================
  # Delta codec (new format)
  # =================================================================

  @doc """
  Serialize a list of operation structs plus metadata into a delta JSON string.

  `meta` accepts `:previous_hash`, `:resulting_hash`, `:migration`, and
  `:generated_at`. Any missing keys default to `nil`.
  """
  def encode_delta(operations, meta \\ %{}) when is_list(operations) do
    meta = Map.new(meta)

    %{
      version: @delta_version,
      previous_hash: Map.get(meta, :previous_hash),
      resulting_hash: Map.get(meta, :resulting_hash),
      migration: Map.get(meta, :migration),
      generated_at: Map.get(meta, :generated_at) || iso8601_now(),
      operations: Enum.map(operations, &encode_op/1)
    }
    |> to_ordered_object()
    |> Jason.encode!(pretty: true)
  end

  @doc """
  Decode a delta JSON string into a map with atom keys: `:version`,
  `:previous_hash`, `:resulting_hash`, `:migration`, `:generated_at`,
  `:operations` (list of operation structs).

  Raises `ArgumentError` if:
    * the JSON is malformed
    * the top-level value is not a JSON object
    * the version field is missing or not equal to #{@delta_version}
      — legacy full-state files must be migrated via
      `mix ash_postgres.migrate_snapshots`.
  """
  def decode_delta(json) when is_binary(json) do
    decoded =
      case Jason.decode(json, keys: :atoms!) do
        {:ok, map} when is_map(map) ->
          map

        {:ok, other} ->
          raise ArgumentError,
                "Expected delta snapshot to be a JSON object, got #{inspect(other, limit: :infinity, printable_limit: 200)}"

        {:error, %Jason.DecodeError{} = err} ->
          raise ArgumentError,
                "Could not parse delta snapshot JSON: #{Exception.message(err)}"
      end

    case Map.get(decoded, :version) do
      @delta_version ->
        %{
          version: @delta_version,
          previous_hash: Map.get(decoded, :previous_hash),
          resulting_hash: Map.get(decoded, :resulting_hash),
          migration: Map.get(decoded, :migration),
          generated_at: Map.get(decoded, :generated_at),
          operations:
            decoded
            |> Map.get(:operations, [])
            |> Enum.map(&decode_op/1)
        }

      other ->
        raise ArgumentError,
              "Expected delta snapshot version #{@delta_version}, got #{inspect(other)}. " <>
                "This looks like a legacy full-state snapshot — run " <>
                "`mix ash_postgres.migrate_snapshots` to convert it."
    end
  end

  @doc "Returns true if the given JSON string is a v2 delta snapshot."
  def delta?(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"version" => @delta_version}} -> true
      _ -> false
    end
  end

  # ---- per-op encode ----

  def encode_op(%Operation.CreateTable{} = op) do
    base_op_json("create_table", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "repo" => op.repo,
      "create_table_options" => op.create_table_options
    })
  end

  def encode_op(%Operation.DropTable{} = op) do
    base_op_json("drop_table", op.table, op.schema, op.multitenancy, %{"repo" => op.repo})
  end

  def encode_op(%Operation.RenameTable{} = op) do
    %{
      "type" => "rename_table",
      "old_table" => op.old_table,
      "new_table" => op.new_table,
      "schema" => op.schema,
      "multitenancy" => encode_multitenancy(op.multitenancy),
      "repo" => op.repo
    }
  end

  def encode_op(%Operation.AddAttribute{} = op) do
    base_op_json("add_attribute", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "attribute" => encode_attribute(op.attribute)
    })
  end

  def encode_op(%Operation.AlterAttribute{} = op) do
    base_op_json("alter_attribute", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "old_attribute" => encode_attribute(op.old_attribute),
      "new_attribute" => encode_attribute(op.new_attribute)
    })
  end

  def encode_op(%Operation.RenameAttribute{} = op) do
    base_op_json("rename_attribute", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "old_attribute" => encode_attribute(op.old_attribute),
      "new_attribute" => encode_attribute(op.new_attribute)
    })
  end

  def encode_op(%Operation.RemoveAttribute{} = op) do
    base_op_json("remove_attribute", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "attribute" => encode_attribute(op.attribute),
      "commented?" => op.commented?
    })
  end

  def encode_op(%Operation.DropForeignKey{} = op) do
    base_op_json("drop_foreign_key", op.table, op.schema, op.multitenancy, %{
      "attribute" => encode_attribute(op.attribute),
      "direction" => op.direction
    })
  end

  def encode_op(%Operation.AlterDeferrability{} = op) do
    %{
      "type" => "alter_deferrability",
      "table" => op.table,
      "schema" => op.schema,
      "references" => encode_references(op.references),
      "direction" => op.direction
    }
  end

  def encode_op(%Operation.AddUniqueIndex{} = op) do
    base_op_json("add_unique_index", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "identity" => encode_identity(op.identity),
      "insert_after_attribute_source" => op.insert_after_attribute_source,
      "concurrently" => op.concurrently
    })
  end

  def encode_op(%Operation.RemoveUniqueIndex{} = op) do
    base_op_json("remove_unique_index", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "identity" => encode_identity(op.identity)
    })
  end

  def encode_op(%Operation.RenameUniqueIndex{} = op) do
    base_op_json("rename_unique_index", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "old_identity" => encode_identity(op.old_identity),
      "new_identity" => encode_identity(op.new_identity)
    })
  end

  def encode_op(%Operation.AddCustomIndex{} = op) do
    base_op_json("add_custom_index", op.table, op.schema, op.multitenancy, %{
      "index" => encode_custom_index(op.index),
      "base_filter" => op.base_filter
    })
  end

  def encode_op(%Operation.RemoveCustomIndex{} = op) do
    base_op_json("remove_custom_index", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "index" => encode_custom_index(op.index),
      "base_filter" => op.base_filter
    })
  end

  def encode_op(%Operation.AddReferenceIndex{} = op) do
    base_op_json("add_reference_index", op.table, op.schema, op.multitenancy, %{
      "source" => op.source
    })
  end

  def encode_op(%Operation.RemoveReferenceIndex{} = op) do
    base_op_json("remove_reference_index", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "source" => op.source
    })
  end

  def encode_op(%Operation.AddPrimaryKey{} = op) do
    %{
      "type" => "add_primary_key",
      "table" => op.table,
      "schema" => op.schema,
      "keys" => op.keys
    }
  end

  def encode_op(%Operation.AddPrimaryKeyDown{} = op) do
    %{
      "type" => "add_primary_key_down",
      "table" => op.table,
      "schema" => op.schema,
      "keys" => op.keys,
      "remove_old?" => op.remove_old?
    }
  end

  def encode_op(%Operation.RemovePrimaryKey{} = op) do
    %{"type" => "remove_primary_key", "table" => op.table, "schema" => op.schema}
  end

  def encode_op(%Operation.RemovePrimaryKeyDown{} = op) do
    %{
      "type" => "remove_primary_key_down",
      "table" => op.table,
      "schema" => op.schema,
      "commented?" => op.commented?
    }
  end

  def encode_op(%Operation.AddCustomStatement{} = op) do
    %{
      "type" => "add_custom_statement",
      "table" => op.table,
      "statement" => encode_custom_statement(op.statement)
    }
  end

  def encode_op(%Operation.RemoveCustomStatement{} = op) do
    %{
      "type" => "remove_custom_statement",
      "table" => op.table,
      "statement" => encode_custom_statement(op.statement)
    }
  end

  def encode_op(%Operation.AddCheckConstraint{} = op) do
    base_op_json("add_check_constraint", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "constraint" => encode_check_constraint(op.constraint)
    })
  end

  def encode_op(%Operation.RemoveCheckConstraint{} = op) do
    base_op_json("remove_check_constraint", op.table, op.schema, op.multitenancy, %{
      "old_multitenancy" => encode_multitenancy(op.old_multitenancy),
      "constraint" => encode_check_constraint(op.constraint)
    })
  end

  def encode_op(%Operation.SetBaseFilter{} = op) do
    base_op_json("set_base_filter", op.table, op.schema, op.multitenancy, %{
      "old_value" => op.old_value,
      "new_value" => op.new_value
    })
  end

  def encode_op(%Operation.SetHasCreateAction{} = op) do
    base_op_json("set_has_create_action", op.table, op.schema, op.multitenancy, %{
      "old_value" => op.old_value,
      "new_value" => op.new_value
    })
  end

  def encode_op(%Operation.SetCreateTableOptions{} = op) do
    base_op_json("set_create_table_options", op.table, op.schema, op.multitenancy, %{
      "old_value" => op.old_value,
      "new_value" => op.new_value
    })
  end

  def encode_op(%Operation.OptOutDropTable{} = op) do
    base_op_json("opt_out_drop_table", op.table, op.schema, op.multitenancy, %{})
  end

  defp base_op_json(type, table, schema, multitenancy, extra) do
    Map.merge(extra, %{
      "type" => type,
      "table" => table,
      "schema" => schema,
      "multitenancy" => encode_multitenancy(multitenancy)
    })
  end

  # ---- per-op decode ----

  def decode_op(%{type: type_string} = map) do
    case Map.get(@type_to_op, type_string) do
      nil ->
        raise ArgumentError,
              "Unknown operation type #{inspect(type_string)} in delta snapshot"

      module ->
        decode_op(module, map)
    end
  end

  defp decode_op(Operation.CreateTable, m) do
    %Operation.CreateTable{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      repo: decode_atom(m.repo),
      create_table_options: Map.get(m, :create_table_options)
    }
  end

  defp decode_op(Operation.DropTable, m) do
    %Operation.DropTable{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      repo: decode_atom(m.repo)
    }
  end

  defp decode_op(Operation.RenameTable, m) do
    %Operation.RenameTable{
      old_table: m.old_table,
      new_table: m.new_table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      repo: decode_atom(m.repo)
    }
  end

  defp decode_op(Operation.AddAttribute, m) do
    %Operation.AddAttribute{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      attribute: decode_attribute(m.attribute, m.table)
    }
  end

  defp decode_op(Operation.AlterAttribute, m) do
    %Operation.AlterAttribute{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      old_attribute: decode_attribute(m.old_attribute, m.table),
      new_attribute: decode_attribute(m.new_attribute, m.table)
    }
  end

  defp decode_op(Operation.RenameAttribute, m) do
    %Operation.RenameAttribute{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      old_attribute: decode_attribute(m.old_attribute, m.table),
      new_attribute: decode_attribute(m.new_attribute, m.table)
    }
  end

  defp decode_op(Operation.RemoveAttribute, m) do
    %Operation.RemoveAttribute{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      attribute: decode_attribute(m.attribute, m.table),
      commented?: Map.get(m, :commented?, true)
    }
  end

  defp decode_op(Operation.DropForeignKey, m) do
    %Operation.DropForeignKey{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      attribute: decode_attribute(m.attribute, m.table),
      direction: decode_atom(m.direction)
    }
  end

  defp decode_op(Operation.AlterDeferrability, m) do
    %Operation.AlterDeferrability{
      table: m.table,
      schema: m.schema,
      references: decode_references(m.references, m.table, nil),
      direction: decode_atom(m.direction)
    }
  end

  defp decode_op(Operation.AddUniqueIndex, m) do
    %Operation.AddUniqueIndex{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      identity: decode_identity(m.identity, m.table),
      insert_after_attribute_source: Map.get(m, :insert_after_attribute_source),
      concurrently: Map.get(m, :concurrently, false)
    }
  end

  defp decode_op(Operation.RemoveUniqueIndex, m) do
    %Operation.RemoveUniqueIndex{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      identity: decode_identity(m.identity, m.table)
    }
  end

  defp decode_op(Operation.RenameUniqueIndex, m) do
    %Operation.RenameUniqueIndex{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      old_identity: decode_identity(m.old_identity, m.table),
      new_identity: decode_identity(m.new_identity, m.table)
    }
  end

  defp decode_op(Operation.AddCustomIndex, m) do
    %Operation.AddCustomIndex{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      index: decode_custom_index(m.index),
      base_filter: Map.get(m, :base_filter)
    }
  end

  defp decode_op(Operation.RemoveCustomIndex, m) do
    %Operation.RemoveCustomIndex{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      index: decode_custom_index(m.index),
      base_filter: Map.get(m, :base_filter)
    }
  end

  defp decode_op(Operation.AddReferenceIndex, m) do
    %Operation.AddReferenceIndex{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      source: decode_atom(m.source)
    }
  end

  defp decode_op(Operation.RemoveReferenceIndex, m) do
    %Operation.RemoveReferenceIndex{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      source: decode_atom(m.source)
    }
  end

  defp decode_op(Operation.AddPrimaryKey, m) do
    %Operation.AddPrimaryKey{
      table: m.table,
      schema: m.schema,
      keys: decode_key_list(m.keys)
    }
  end

  defp decode_op(Operation.AddPrimaryKeyDown, m) do
    %Operation.AddPrimaryKeyDown{
      table: m.table,
      schema: m.schema,
      keys: decode_key_list(m.keys),
      remove_old?: Map.get(m, :remove_old?)
    }
  end

  defp decode_op(Operation.RemovePrimaryKey, m) do
    %Operation.RemovePrimaryKey{table: m.table, schema: m.schema}
  end

  defp decode_op(Operation.RemovePrimaryKeyDown, m) do
    %Operation.RemovePrimaryKeyDown{
      table: m.table,
      schema: m.schema,
      commented?: Map.get(m, :commented?, false)
    }
  end

  defp decode_op(Operation.AddCustomStatement, m) do
    %Operation.AddCustomStatement{table: m.table, statement: decode_custom_statement(m.statement)}
  end

  defp decode_op(Operation.RemoveCustomStatement, m) do
    %Operation.RemoveCustomStatement{
      table: m.table,
      statement: decode_custom_statement(m.statement)
    }
  end

  defp decode_op(Operation.AddCheckConstraint, m) do
    %Operation.AddCheckConstraint{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      constraint: decode_check_constraint(m.constraint)
    }
  end

  defp decode_op(Operation.RemoveCheckConstraint, m) do
    %Operation.RemoveCheckConstraint{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_multitenancy: decode_multitenancy(Map.get(m, :old_multitenancy)),
      constraint: decode_check_constraint(m.constraint)
    }
  end

  defp decode_op(Operation.SetBaseFilter, m) do
    %Operation.SetBaseFilter{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_value: Map.get(m, :old_value),
      new_value: Map.get(m, :new_value)
    }
  end

  defp decode_op(Operation.SetHasCreateAction, m) do
    %Operation.SetHasCreateAction{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_value: Map.get(m, :old_value),
      new_value: Map.get(m, :new_value)
    }
  end

  defp decode_op(Operation.SetCreateTableOptions, m) do
    %Operation.SetCreateTableOptions{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy),
      old_value: Map.get(m, :old_value),
      new_value: Map.get(m, :new_value)
    }
  end

  defp decode_op(Operation.OptOutDropTable, m) do
    %Operation.OptOutDropTable{
      table: m.table,
      schema: m.schema,
      multitenancy: decode_multitenancy(m.multitenancy)
    }
  end

  # =================================================================
  # Nested shape helpers — shared between full-state and delta
  # =================================================================

  @doc false
  def encode_attribute(attribute) do
    attribute
    |> Map.put_new(:references, nil)
    |> Map.update!(:references, fn
      nil ->
        nil

      references ->
        encode_references(references)
    end)
    |> Map.update!(:type, fn type ->
      sanitize_type(type, attribute[:size], attribute[:precision], attribute[:scale])
    end)
    # `:order` is added to op attributes by the generator for migration-emission
    # sorting; it's not part of the logical attribute state and must not be
    # persisted (otherwise it drifts from the desired state on re-read).
    |> Map.delete(:order)
    |> Map.delete(:__spark_metadata__)
  end

  @doc false
  def decode_attribute(attribute, table) do
    type = load_type(attribute.type)

    attribute =
      if Map.has_key?(attribute, :name) do
        Map.put(attribute, :source, maybe_to_atom(attribute.name))
      else
        Map.update!(attribute, :source, &maybe_to_atom/1)
      end

    attribute
    |> Map.put(:type, type)
    |> Map.put_new(:size, nil)
    |> Map.put_new(:precision, nil)
    |> Map.put_new(:scale, nil)
    |> Map.put_new(:default, "nil")
    |> Map.update!(:default, &(&1 || "nil"))
    |> Map.update!(:references, fn
      nil -> nil
      references -> decode_references(references, table, attribute.source)
    end)
  end

  defp encode_references(references) do
    Map.update!(references, :on_delete, &(&1 && references_on_delete_to_binary(&1)))
  end

  defp decode_references(references, table, source_attribute) do
    references
    |> rewrite(
      destination_field: :destination_attribute,
      destination_field_default: :destination_attribute_default,
      destination_field_generated: :destination_attribute_generated
    )
    |> Map.delete(:ignore)
    |> rewrite(:ignore?, :ignore)
    |> Map.update!(:destination_attribute, &maybe_to_atom/1)
    |> Map.put_new(:deferrable, false)
    |> Map.update!(:deferrable, fn
      "initially" -> :initially
      other -> other
    end)
    |> Map.put_new(:schema, nil)
    |> Map.put_new(:destination_attribute_default, "nil")
    |> Map.put_new(:destination_attribute_generated, false)
    |> Map.put_new(:on_delete, nil)
    |> Map.put_new(:on_update, nil)
    |> Map.update!(:on_delete, &(&1 && load_references_on_delete(&1)))
    |> Map.update!(:on_update, &(&1 && maybe_to_atom(&1)))
    |> Map.put_new(:index?, false)
    |> Map.put_new(:match_with, nil)
    |> Map.put_new(:match_type, nil)
    |> Map.update!(
      :match_with,
      &(&1 && Enum.into(&1, %{}, fn {k, v} -> {maybe_to_atom(k), maybe_to_atom(v)} end))
    )
    |> Map.update!(:match_type, &(&1 && maybe_to_atom(&1)))
    |> Map.put(
      :name,
      Map.get(references, :name) ||
        reference_default_name(table, source_attribute)
    )
    |> Map.put_new(:multitenancy, %{attribute: nil, strategy: nil, global: nil})
    |> Map.update!(:multitenancy, &decode_multitenancy/1)
    |> sanitize_name(table)
  end

  defp reference_default_name(table, nil), do: "#{table}_fkey"
  defp reference_default_name(table, source), do: "#{table}_#{source}_fkey"

  defp references_on_delete_to_binary(value) when is_atom(value), do: value
  defp references_on_delete_to_binary({:nilify, columns}), do: [:nilify, columns]

  defp sanitize_type({:array, type}, size, scale, precision) do
    ["array", sanitize_type(type, size, scale, precision)]
  end

  defp sanitize_type(type, _, _, _), do: type

  defp load_type(["array", type]), do: {:array, load_type(type)}
  defp load_type([type | _]), do: String.to_existing_atom(type)
  defp load_type(type), do: maybe_to_atom(type)

  defp load_references_on_delete(["nilify", columns]) when is_list(columns) do
    {:nilify, Enum.map(columns, &maybe_to_atom/1)}
  end

  defp load_references_on_delete(value), do: maybe_to_atom(value)

  @doc false
  def encode_identity(identity) do
    keys =
      Enum.map(identity.keys, fn
        value when is_binary(value) -> %{"type" => "string", "value" => value}
        value when is_atom(value) -> %{"type" => "atom", "value" => value}
      end)

    %{identity | keys: keys}
    |> Map.delete(:__spark_metadata__)
  end

  @doc false
  def decode_identity(identity, table) do
    identity
    |> Map.update!(:name, &maybe_to_atom/1)
    |> add_index_name(table)
    |> Map.put_new(:base_filter, nil)
    |> Map.put_new(:all_tenants?, false)
    |> Map.put_new(:where, nil)
    |> Map.put_new(:nils_distinct?, true)
    |> Map.update!(:keys, &decode_key_list/1)
  end

  defp decode_key_list(keys) do
    Enum.map(keys, fn
      %{type: "atom", value: value} ->
        maybe_to_atom(value)

      %{type: "string", value: value} ->
        value

      value when is_binary(value) ->
        if String.contains?(value, "(") do
          value
        else
          maybe_to_atom(value)
        end

      value when is_atom(value) ->
        value
    end)
  end

  @doc false
  def encode_custom_index(index) do
    fields =
      Enum.map(index.fields, fn
        field when is_atom(field) -> %{type: "atom", value: field}
        field when is_binary(field) -> %{type: "string", value: field}
      end)

    %{index | fields: fields}
    |> Map.delete(:__spark_metadata__)
  end

  @doc false
  def decode_custom_index(custom_index) do
    custom_index
    |> Map.update(:fields, [], fn fields ->
      Enum.map(fields, fn
        %{type: "atom", value: field} -> maybe_to_atom(field)
        %{type: "string", value: field} -> field
        field -> field
      end)
    end)
    |> Map.put_new(:include, [])
    |> Map.put_new(:nulls_distinct, true)
    |> Map.put_new(:message, nil)
    |> Map.put_new(:all_tenants?, false)
  end

  @doc false
  def encode_custom_statement(statement) do
    Map.delete(statement, :__spark_metadata__)
  end

  @doc false
  def decode_custom_statement(statement) do
    Map.update!(statement, :name, &maybe_to_atom/1)
  end

  @doc false
  def encode_check_constraint(constraint) do
    Map.delete(constraint, :__spark_metadata__)
  end

  @doc false
  def decode_check_constraint(constraint) do
    Map.update!(constraint, :attribute, fn attribute ->
      attribute
      |> List.wrap()
      |> Enum.map(&maybe_to_atom/1)
    end)
  end

  @doc false
  def encode_multitenancy(nil), do: %{"strategy" => nil, "attribute" => nil, "global" => nil}

  def encode_multitenancy(mt) do
    %{
      "strategy" => mt.strategy,
      "attribute" => mt.attribute,
      "global" => Map.get(mt, :global)
    }
  end

  @doc false
  def decode_multitenancy(nil), do: %{strategy: nil, attribute: nil, global: nil}

  def decode_multitenancy(mt) do
    %{
      strategy: mt |> Map.get(:strategy) |> decode_optional_atom(),
      attribute: mt |> Map.get(:attribute) |> decode_optional_atom(),
      global: Map.get(mt, :global)
    }
  end

  defp decode_optional_atom(nil), do: nil
  defp decode_optional_atom(value), do: maybe_to_atom(value)

  defp decode_atom(nil), do: nil
  defp decode_atom(value), do: maybe_to_atom(value)

  defp rewrite(map, keys) do
    Enum.reduce(keys, map, fn {key, to}, map ->
      rewrite(map, key, to)
    end)
  end

  defp rewrite(map, key, to) do
    if Map.has_key?(map, key) do
      map
      |> Map.put(to, Map.get(map, key))
      |> Map.delete(key)
    else
      map
    end
  end

  defp sanitize_name(reference, table) do
    if String.starts_with?(reference.name, "_") do
      Map.put(reference, :name, "#{table}#{reference.name}")
    else
      reference
    end
  end

  defp add_index_name(%{name: name} = index, table) do
    Map.put_new(index, :index_name, "#{table}_#{name}_unique_index")
  end

  defp maybe_to_atom(value) when is_atom(value), do: value
  # sobelow_skip ["DOS.StringToAtom"]
  # Snapshot files are developer-committed and reviewed. This matches the
  # pattern already skipped in migration_generator.ex.
  defp maybe_to_atom(value), do: String.to_atom(value)

  defp iso8601_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
