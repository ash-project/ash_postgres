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
    directory = snapshot_directory(snapshot, opts)

    with {:ok, files} <- list_delta_files(directory, opts),
         files when files != [] <- files do
      initial = empty_state(snapshot)

      {state, _last_hash} =
        Enum.reduce(files, {initial, nil}, fn file_path, acc ->
          apply_file(file_path, acc)
        end)

      Map.put(state, :empty?, state_empty?(state))
    else
      _ -> nil
    end
  end

  @doc """
  Produce a list of operation structs that, when reduced from an empty state,
  reconstruct the given existing state.

  Uses the same machinery the live generator uses for brand-new tables — we
  invoke the migration generator's empty-snapshot diff branch so the ops are
  byte-identical with what `do_fetch_operations/4` would emit on first-time
  table creation.
  """
  def state_to_initial_delta(state) do
    AshPostgres.MigrationGenerator.initial_operations_for_state(state)
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
      empty?: true,
      multitenancy: %{attribute: nil, strategy: nil, global: nil}
    }
  end

  # =================================================================
  # Internals
  # =================================================================

  defp state_empty?(state) do
    state.attributes == [] and state.identities == [] and state.custom_indexes == [] and
      state.custom_statements == [] and state.check_constraints == []
  end

  defp snapshot_directory(snapshot, opts) do
    folder = AshPostgres.MigrationGenerator.get_snapshot_folder(snapshot, opts)
    AshPostgres.MigrationGenerator.get_snapshot_path(snapshot, folder)
  end

  defp list_delta_files(directory, opts) do
    cond do
      not File.exists?(directory) ->
        {:ok, []}

      not File.dir?(directory) ->
        {:ok, []}

      true ->
        files =
          directory
          |> File.ls!()
          |> Enum.filter(
            &(String.match?(&1, ~r/^\d{14}\.json$/) or
                (opts.dev and String.match?(&1, ~r/^\d{14}_dev\.json$/)))
          )
          |> Enum.sort()
          |> Enum.map(&Path.join(directory, &1))

        {:ok, files}
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
    # therefore a metadata refresh — it sets the schema, multitenancy, and
    # repo context but does not require the state to be empty.
    %{
      state
      | schema: op.schema,
        multitenancy: op.multitenancy,
        empty?: false
    }
    |> maybe_put(:repo, op.repo)
  end

  def apply_op(state, %Operation.DropTable{}) do
    # Reset to a fresh empty state but preserve identity (table/schema/repo)
    # so subsequent deltas in the same file can rebuild on top.
    %{
      empty_state(%{table: state.table, schema: state.schema, repo: state.repo})
      | empty?: true
    }
  end

  def apply_op(state, %Operation.RenameTable{} = op) do
    if state.table != op.old_table do
      throw_conflict(
        "RenameTable expected old_table=#{inspect(op.old_table)} but current state table=#{inspect(state.table)}"
      )
    end

    %{state | table: op.new_table}
  end

  def apply_op(state, %Operation.AddAttribute{attribute: attr}) do
    if Enum.any?(state.attributes, &(&1.source == attr.source)) do
      throw_conflict("AddAttribute: attribute #{inspect(attr.source)} already exists")
    end

    %{state | attributes: state.attributes ++ [attr], empty?: false}
  end

  def apply_op(state, %Operation.RemoveAttribute{attribute: attr}) do
    if not Enum.any?(state.attributes, &(&1.source == attr.source)) do
      throw_conflict("RemoveAttribute: attribute #{inspect(attr.source)} not present")
    end

    %{state | attributes: Enum.reject(state.attributes, &(&1.source == attr.source))}
  end

  def apply_op(state, %Operation.AlterAttribute{old_attribute: old_attr, new_attribute: new_attr}) do
    case Enum.find_index(state.attributes, &(&1.source == old_attr.source)) do
      nil ->
        throw_conflict("AlterAttribute: attribute #{inspect(old_attr.source)} not present")

      idx ->
        %{state | attributes: List.replace_at(state.attributes, idx, new_attr)}
    end
  end

  def apply_op(state, %Operation.RenameAttribute{
        old_attribute: old_attr,
        new_attribute: new_attr
      }) do
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

  def apply_op(state, %Operation.AddUniqueIndex{identity: identity}) do
    if Enum.any?(state.identities, &(&1.name == identity.name)) do
      throw_conflict("AddUniqueIndex: identity #{inspect(identity.name)} already present")
    end

    %{state | identities: state.identities ++ [identity], empty?: false}
  end

  def apply_op(state, %Operation.RemoveUniqueIndex{identity: identity}) do
    if not Enum.any?(state.identities, &(&1.name == identity.name)) do
      throw_conflict("RemoveUniqueIndex: identity #{inspect(identity.name)} not present")
    end

    %{state | identities: Enum.reject(state.identities, &(&1.name == identity.name))}
  end

  def apply_op(state, %Operation.RenameUniqueIndex{
        old_identity: old_id,
        new_identity: new_id
      }) do
    case Enum.find_index(state.identities, &(&1.name == old_id.name)) do
      nil ->
        throw_conflict("RenameUniqueIndex: identity #{inspect(old_id.name)} not present")

      idx ->
        %{state | identities: List.replace_at(state.identities, idx, new_id)}
    end
  end

  def apply_op(state, %Operation.AddCustomIndex{index: index}) do
    if Enum.any?(state.custom_indexes, &same_custom_index?(&1, index)) do
      throw_conflict("AddCustomIndex: index already present")
    end

    %{state | custom_indexes: state.custom_indexes ++ [index], empty?: false}
  end

  def apply_op(state, %Operation.RemoveCustomIndex{index: index}) do
    if not Enum.any?(state.custom_indexes, &same_custom_index?(&1, index)) do
      throw_conflict("RemoveCustomIndex: index not present")
    end

    %{state | custom_indexes: Enum.reject(state.custom_indexes, &same_custom_index?(&1, index))}
  end

  def apply_op(state, %Operation.AddCustomStatement{statement: stmt}) do
    if Enum.any?(state.custom_statements, &(&1.name == stmt.name)) do
      throw_conflict("AddCustomStatement: statement #{inspect(stmt.name)} already present")
    end

    %{state | custom_statements: state.custom_statements ++ [stmt], empty?: false}
  end

  def apply_op(state, %Operation.RemoveCustomStatement{statement: stmt}) do
    if not Enum.any?(state.custom_statements, &(&1.name == stmt.name)) do
      throw_conflict("RemoveCustomStatement: statement #{inspect(stmt.name)} not present")
    end

    %{state | custom_statements: Enum.reject(state.custom_statements, &(&1.name == stmt.name))}
  end

  def apply_op(state, %Operation.AddCheckConstraint{constraint: c}) do
    if Enum.any?(state.check_constraints, &(&1.name == c.name)) do
      throw_conflict("AddCheckConstraint: constraint #{inspect(c.name)} already present")
    end

    %{state | check_constraints: state.check_constraints ++ [c], empty?: false}
  end

  def apply_op(state, %Operation.RemoveCheckConstraint{constraint: c}) do
    if not Enum.any?(state.check_constraints, &(&1.name == c.name)) do
      throw_conflict("RemoveCheckConstraint: constraint #{inspect(c.name)} not present")
    end

    %{state | check_constraints: Enum.reject(state.check_constraints, &(&1.name == c.name))}
  end

  def apply_op(state, %Operation.SetBaseFilter{new_value: v}), do: %{state | base_filter: v}

  def apply_op(state, %Operation.SetHasCreateAction{new_value: v}),
    do: %{state | has_create_action: v}

  def apply_op(state, %Operation.SetCreateTableOptions{new_value: _v}), do: state

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

  defp same_custom_index?(a, b) do
    Map.get(a, :name) == Map.get(b, :name) and Map.get(a, :fields) == Map.get(b, :fields)
  end

  defp throw_conflict(reason), do: throw({:reducer_error, reason})

  defp maybe_put(state, _key, nil), do: state
  defp maybe_put(state, key, value), do: Map.put(state, key, value)
end
