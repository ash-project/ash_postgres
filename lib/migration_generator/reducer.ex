# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationGenerator.Reducer do
  @moduledoc false

  alias AshPostgres.MigrationGenerator.Operation
  alias AshPostgres.MigrationGenerator.Operation.Codec

  defmodule ConflictError do
    @moduledoc false
    defexception [:message, :file, :op_index, :op_type, :reason]

    @impl true
    def exception(attrs) do
      file = Keyword.get(attrs, :file)
      op_index = Keyword.get(attrs, :op_index)
      op_type = Keyword.get(attrs, :op_type)
      reason = Keyword.get(attrs, :reason)

      message =
        "Delta reduction failed in #{file || "<unknown>"} " <>
          "at op index #{op_index || "?"} (#{op_type || "?"}): #{reason}"

      %__MODULE__{
        message: message,
        file: file,
        op_index: op_index,
        op_type: op_type,
        reason: reason
      }
    end
  end

  defmodule LegacyFormatError do
    @moduledoc false
    defexception [:message, :file]

    @impl true
    def exception(attrs) do
      file = Keyword.get(attrs, :file)

      message =
        "Found legacy full-state snapshot at #{file || "<unknown>"}. " <>
          "Run `mix ash_postgres.migrate_snapshots` to convert legacy snapshots to the delta format."

      %__MODULE__{message: message, file: file}
    end
  end

  @doc """
  Load and reduce all delta snapshot files under the directory implied by
  the given snapshot. Returns the reduced existing-state map, or `nil` if
  no deltas exist (signaling a fresh table).

  Raises `LegacyFormatError` if any file in the directory is not a v2 delta.
  Raises `ConflictError` if any operation fails to apply cleanly.
  """
  def load_reduced_state(snapshot, opts) do
    files = list_delta_files(snapshot_directory(snapshot, opts), opts)

    if files == [] do
      nil
    else
      {state, _last_hash} =
        Enum.reduce(files, {empty_state(snapshot), nil}, &apply_file/2)

      state
    end
  end

  @doc "The empty starting-state for a given snapshot (path + multitenancy context)."
  def empty_state(snapshot) do
    %{
      attributes: [],
      identities: [],
      schema: snapshot.schema,
      custom_indexes: [],
      custom_statements: [],
      check_constraints: [],
      table: snapshot.table,
      repo: snapshot.repo,
      base_filter: nil,
      has_create_action: true,
      drop_table_opted_out: false,
      create_table_options: nil,
      empty?: true,
      multitenancy: %{attribute: nil, strategy: nil, global: nil}
    }
  end

  # =================================================================
  # Internals
  # =================================================================

  defp snapshot_directory(snapshot, opts) do
    folder = AshPostgres.MigrationGenerator.get_snapshot_folder(snapshot, opts)
    AshPostgres.MigrationGenerator.get_snapshot_path(snapshot, folder)
  end

  defp list_delta_files(directory, opts) do
    # One syscall — if the directory doesn't exist or isn't readable, we treat
    # it the same as "no deltas".
    case File.ls(directory) do
      {:ok, names} ->
        names
        |> Enum.filter(&AshPostgres.MigrationGenerator.snapshot_filename?(&1, opts.dev))
        |> Enum.sort()
        |> Enum.map(&Path.join(directory, &1))

      {:error, _} ->
        []
    end
  end

  defp apply_file(file_path, {state, prev_hash}) do
    contents = File.read!(file_path)

    if !Codec.delta?(contents) do
      raise LegacyFormatError, file: file_path
    end

    delta = Codec.decode_delta(contents)

    # Validate previous_hash chain. We only enforce this when both values are
    # present — initial deltas set previous_hash: null.
    if delta.previous_hash != nil and prev_hash != nil and delta.previous_hash != prev_hash do
      raise ConflictError,
        file: file_path,
        op_index: 0,
        op_type: "<delta>",
        reason:
          "previous_hash #{inspect(delta.previous_hash)} does not match prior resulting_hash " <>
            "#{inspect(prev_hash)} — the delta chain has diverged"
    end

    new_state =
      delta.operations
      |> Enum.with_index()
      |> Enum.reduce(state, fn {op, idx}, acc ->
        try do
          apply_op(acc, op)
        rescue
          err in [ConflictError] ->
            reraise err, __STACKTRACE__

          err ->
            reraise ConflictError.exception(
                      file: file_path,
                      op_index: idx,
                      op_type: op_type_string(op),
                      reason: Exception.message(err)
                    ),
                    __STACKTRACE__
        catch
          :throw, {:reducer_error, reason} ->
            raise ConflictError,
              file: file_path,
              op_index: idx,
              op_type: op_type_string(op),
              reason: reason
        end
      end)

    {new_state, delta.resulting_hash || prev_hash}
  end

  defp op_type_string(%mod{}), do: mod |> Module.split() |> List.last() |> Macro.underscore()

  # =================================================================
  # apply_op — per-operation state mutation + fail-loud invariants
  # =================================================================

  @doc false
  def apply_op(state, op)

  def apply_op(state, %Operation.CreateTable{} = op) do
    # Deltas are persisted in migration-emission order, which places CreateTable
    # AFTER the AddAttribute ops that populate the table. Applying it is
    # therefore a metadata refresh — it sets the table, schema, multitenancy,
    # scalar fields (create_table_options / base_filter / has_create_action),
    # and repo context but does not require the state to be empty.
    #
    # Setting state.table from op.table is important for the rename chain:
    # a subsequent RenameTable op compares state.table to op.old_table, so
    # state.table must start from the delta's original table name (which may
    # differ from the current resource's table).
    %{
      state
      | table: op.table,
        schema: op.schema,
        multitenancy: op.multitenancy,
        create_table_options: op.create_table_options,
        base_filter: op.base_filter,
        has_create_action: op.has_create_action,
        empty?: false
    }
    |> maybe_put(:repo, op.repo)
  end

  def apply_op(state, %Operation.DropTable{}) do
    # Reset to a fresh empty state but preserve identity (table/schema/repo)
    # so subsequent deltas in the same file can rebuild on top.
    empty_state(%{table: state.table, schema: state.schema, repo: state.repo})
  end

  def apply_op(state, %Operation.RenameTable{} = op) do
    if state.table != op.old_table do
      throw_conflict(
        "RenameTable expected old_table=#{inspect(op.old_table)} but current state table=#{inspect(state.table)}"
      )
    end

    %{state | table: op.new_table}
  end

  def apply_op(state, %Operation.AddAttribute{attribute: attr}),
    do:
      add_to_coll(state, :attributes, attr, &(&1.source == attr.source), fn ->
        "AddAttribute: attribute #{inspect(attr.source)} already exists"
      end)

  def apply_op(state, %Operation.RemoveAttribute{attribute: attr}),
    do:
      remove_from_coll(state, :attributes, &(&1.source == attr.source), fn ->
        "RemoveAttribute: attribute #{inspect(attr.source)} not present"
      end)

  def apply_op(state, %Operation.AlterAttribute{old_attribute: old_attr, new_attribute: new_attr}),
    do:
      replace_in_coll(state, :attributes, &(&1.source == old_attr.source), new_attr, fn ->
        "AlterAttribute: attribute #{inspect(old_attr.source)} not present"
      end)

  def apply_op(state, %Operation.RenameAttribute{
        old_attribute: old_attr,
        new_attribute: new_attr
      }) do
    # Preserve the check order from the pre-refactor version: missing source
    # is reported before existing destination. Callers and error-matching tests
    # rely on the "source not present" message for the common misuse case of
    # applying a rename against a mutated state.
    case Enum.find_index(state.attributes, &(&1.source == old_attr.source)) do
      nil ->
        throw_conflict("RenameAttribute: source #{inspect(old_attr.source)} not present")

      idx ->
        if old_attr.source != new_attr.source and
             Enum.any?(state.attributes, &(&1.source == new_attr.source)) do
          throw_conflict(
            "RenameAttribute: destination #{inspect(new_attr.source)} already exists"
          )
        end

        %{state | attributes: List.replace_at(state.attributes, idx, new_attr)}
    end
  end

  def apply_op(state, %Operation.AddUniqueIndex{identity: identity}),
    do:
      add_to_coll(state, :identities, identity, &(&1.name == identity.name), fn ->
        "AddUniqueIndex: identity #{inspect(identity.name)} already present"
      end)

  def apply_op(state, %Operation.RemoveUniqueIndex{identity: identity}),
    do:
      remove_from_coll(state, :identities, &(&1.name == identity.name), fn ->
        "RemoveUniqueIndex: identity #{inspect(identity.name)} not present"
      end)

  def apply_op(state, %Operation.RenameUniqueIndex{
        old_identity: old_id,
        new_identity: new_id
      }),
      do:
        replace_in_coll(state, :identities, &(&1.name == old_id.name), new_id, fn ->
          "RenameUniqueIndex: identity #{inspect(old_id.name)} not present"
        end)

  def apply_op(state, %Operation.AddCustomIndex{index: index}),
    do:
      add_to_coll(state, :custom_indexes, index, &same_custom_index?(&1, index), fn ->
        "AddCustomIndex: index already present"
      end)

  def apply_op(state, %Operation.RemoveCustomIndex{index: index}),
    do:
      remove_from_coll(state, :custom_indexes, &same_custom_index?(&1, index), fn ->
        "RemoveCustomIndex: index not present"
      end)

  def apply_op(state, %Operation.AddCustomStatement{statement: stmt}),
    do:
      add_to_coll(state, :custom_statements, stmt, &(&1.name == stmt.name), fn ->
        "AddCustomStatement: statement #{inspect(stmt.name)} already present"
      end)

  def apply_op(state, %Operation.RemoveCustomStatement{statement: stmt}),
    do:
      remove_from_coll(state, :custom_statements, &(&1.name == stmt.name), fn ->
        "RemoveCustomStatement: statement #{inspect(stmt.name)} not present"
      end)

  def apply_op(state, %Operation.AddCheckConstraint{constraint: c}),
    do:
      add_to_coll(state, :check_constraints, c, &(&1.name == c.name), fn ->
        "AddCheckConstraint: constraint #{inspect(c.name)} already present"
      end)

  def apply_op(state, %Operation.RemoveCheckConstraint{constraint: c}),
    do:
      remove_from_coll(state, :check_constraints, &(&1.name == c.name), fn ->
        "RemoveCheckConstraint: constraint #{inspect(c.name)} not present"
      end)

  def apply_op(state, %Operation.OptOutDropTable{}),
    do: %{state | drop_table_opted_out: true}

  # State-neutral ops — persisted for migration round-trip fidelity but do not
  # mutate the reduced state (their structural effect is captured by the
  # paired AddAttribute/AlterAttribute/RemoveAttribute).
  def apply_op(state, %Operation.AddPrimaryKey{}), do: state
  def apply_op(state, %Operation.AddPrimaryKeyDown{}), do: state
  def apply_op(state, %Operation.RemovePrimaryKey{}), do: state
  def apply_op(state, %Operation.RemovePrimaryKeyDown{}), do: state
  def apply_op(state, %Operation.DropForeignKey{}), do: state
  def apply_op(state, %Operation.AlterDeferrability{}), do: state
  def apply_op(state, %Operation.AddReferenceIndex{}), do: state
  def apply_op(state, %Operation.RemoveReferenceIndex{}), do: state

  # =================================================================
  # Collection helpers — `error_msg_fn` is a thunk so we only build the
  # (inspect-heavy) message when the invariant actually fails.
  # =================================================================

  defp add_to_coll(state, key, value, match_fn, error_msg_fn) do
    if Enum.any?(Map.fetch!(state, key), match_fn) do
      throw_conflict(error_msg_fn.())
    end

    state
    |> Map.update!(key, &(&1 ++ [value]))
    |> Map.put(:empty?, false)
  end

  defp remove_from_coll(state, key, match_fn, error_msg_fn) do
    if !Enum.any?(Map.fetch!(state, key), match_fn) do
      throw_conflict(error_msg_fn.())
    end

    Map.update!(state, key, &Enum.reject(&1, match_fn))
  end

  defp replace_in_coll(state, key, match_fn, new_value, error_msg_fn) do
    case Enum.find_index(Map.fetch!(state, key), match_fn) do
      nil ->
        throw_conflict(error_msg_fn.())

      idx ->
        Map.update!(state, key, &List.replace_at(&1, idx, new_value))
    end
  end

  defp same_custom_index?(a, b) do
    Map.get(a, :name) == Map.get(b, :name) and Map.get(a, :fields) == Map.get(b, :fields)
  end

  defp throw_conflict(reason), do: throw({:reducer_error, reason})

  defp maybe_put(state, _key, nil), do: state
  defp maybe_put(state, key, value), do: Map.put(state, key, value)
end
