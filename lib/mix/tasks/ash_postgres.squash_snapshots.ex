# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshPostgres.SquashSnapshots do
  use Mix.Task

  alias AshPostgres.MigrationGenerator
  alias AshPostgres.MigrationGenerator.Operation.Codec

  @shortdoc "Cleans snapshots folder, leaving only one snapshot per resource"

  @switches [
    into: :string,
    snapshot_path: :string,
    quiet: :boolean,
    dry_run: :boolean,
    check: :boolean,
    include_dev: :boolean
  ]

  @moduledoc """
  Cleans snapshots folder, leaving only one snapshot per resource.

  Works for both the legacy full-state snapshot format and the new delta
  snapshot format:

  * **Full-state folders** — older snapshots are deleted and the newest is
    renamed per the `--into` flag.
  * **Delta folders** — all deltas are reduced to a single state, then
    re-emitted as one `initial` v2 delta whose ops reconstruct the full
    current state from empty. Preserves round-trip fidelity with the live
    generator.

  Mixed folders (both formats present) are an error — run
  `mix ash_postgres.migrate_snapshots` first.

  ## Examples

      mix ash_postgres.squash_snapshots
      mix ash_postgres.squash_snapshots --check --quiet
      mix ash_postgres.squash_snapshots --into zero
      mix ash_postgres.squash_snapshots --dry-run

  ## Command line options

  * `--into` -
      `last`, `first` or `zero`. The default is `last`. Determines which name to use for
      a remaining snapshot. `last` keeps the name of the last snapshot, `first` renames it to the previously first,
      `zero` sets name with fourteen zeros.
  * `--snapshot-path` - a custom path to stored snapshots. The default is "priv/resource_snapshots".
  * `--quiet` - no messages will be printed.
  * `--dry-run` - no files are touched, instead prints folders that have snapshots to squash.
  * `--check` - no files are touched, instead returns an exit(1) code if there are snapshots to squash.
  * `--include-dev` - include `*_dev.json` files in the squash (default: skip them). Delta-mode squash aborts if dev files are present and this flag is not set.
  """

  @timestamp_regex ~r/^\d{14}\.json$/
  @dev_regex ~r/^\d{14}_dev\.json$/

  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: @switches)

    opts =
      opts
      |> Map.new()
      |> Map.put_new(:into, "last")
      |> Map.put_new(:snapshot_path, "priv/resource_snapshots")
      |> Map.put_new(:quiet, false)
      |> Map.put_new(:dry_run, false)
      |> Map.put_new(:check, false)
      |> Map.put_new(:include_dev, false)
      |> Map.update!(:into, fn
        "last" -> :last
        "first" -> :first
        "zero" -> :zero
        _other -> raise "Valid values for --into flag are `last`, `first` and `zero`."
      end)

    squashable =
      opts.snapshot_path
      |> Path.join("**/*.json")
      |> Path.wildcard()
      |> Enum.reject(&String.contains?(&1, ".legacy_backup"))
      |> Enum.filter(&String.match?(Path.basename(&1), @timestamp_regex))
      |> Enum.group_by(&Path.dirname(&1))
      |> Enum.reduce([], fn {folder, snapshots}, acc ->
        case classify_folder(folder, snapshots) do
          {:delta, delta_files} ->
            build_squashable_for_delta(folder, delta_files, opts, acc)

          {:full, full_files} ->
            build_squashable_for_full(folder, full_files, opts, acc)

          {:mixed, _} ->
            abort_mixed(folder)
        end
      end)
      |> Enum.reverse()

    cond do
      Enum.empty?(squashable) ->
        print(opts, "No snapshots to squash.")

      opts.dry_run ->
        print(opts, "Snapshots in following folders would have been squashed in non-dry run:")
        print(opts, Enum.map_join(squashable, "\n", fn {folder, _, _, _, _} -> folder end))

        if opts.check do
          exit({:shutdown, 1})
        end

      opts.check ->
        print(opts, """
        Snapshots would have been squashed, but the --check flag was provided.

        To see what snapshots would have been squashed, run with the --dry-run
        flag. To squash those snapshots, run without either flag.
        """)

        exit({:shutdown, 1})

      true ->
        Enum.each(squashable, &apply_squash(&1, opts))
    end
  end

  # Each squashable entry: {folder, all_files, last_file, into_path, format}
  defp build_squashable_for_full(folder, snapshots, opts, acc) do
    last_snapshot = Enum.max(snapshots)
    into_snapshot = into_path(opts.into, folder, snapshots)

    if length(snapshots) > 1 or last_snapshot != into_snapshot do
      [{folder, snapshots, last_snapshot, into_snapshot, :full} | acc]
    else
      acc
    end
  end

  defp build_squashable_for_delta(folder, snapshots, opts, acc) do
    has_dev? =
      folder
      |> File.ls!()
      |> Enum.any?(&String.match?(&1, @dev_regex))

    if has_dev? and not opts.include_dev do
      raise """
      Delta folder #{folder} contains *_dev.json files. Refusing to squash without
      `--include-dev`. Either commit the dev deltas via `mix ash.codegen <name>`
      first, or re-run this task with `--include-dev` to squash them together.
      """
    end

    last_snapshot = Enum.max(snapshots)
    into_snapshot = into_path(opts.into, folder, snapshots)

    if length(snapshots) > 1 or last_snapshot != into_snapshot do
      [{folder, snapshots, last_snapshot, into_snapshot, :delta} | acc]
    else
      acc
    end
  end

  defp into_path(:last, _folder, snapshots), do: Enum.max(snapshots)
  defp into_path(:first, _folder, snapshots), do: Enum.min(snapshots)
  defp into_path(:zero, folder, _snapshots), do: Path.join(folder, "00000000000000.json")

  defp classify_folder(folder, files) do
    {deltas, fulls} =
      Enum.split_with(files, fn path ->
        case File.read(path) do
          {:ok, contents} -> Codec.delta?(contents)
          _ -> false
        end
      end)

    cond do
      fulls == [] and deltas != [] -> {:delta, deltas}
      deltas == [] and fulls != [] -> {:full, fulls}
      true -> {:mixed, folder}
    end
  end

  defp abort_mixed(folder) do
    raise """
    Folder #{folder} contains a mix of legacy full-state and v2 delta snapshots.
    Run `mix ash_postgres.migrate_snapshots` first, or clean up the directory
    manually before running squash.
    """
  end

  defp apply_squash({folder, snapshots, last_snapshot, into_snapshot, :full}, _opts) do
    for snapshot <- snapshots, snapshot != last_snapshot do
      File.rm!(snapshot)
    end

    if last_snapshot != into_snapshot do
      File.rename!(last_snapshot, into_snapshot)
    end

    _ = folder
    :ok
  end

  defp apply_squash({_folder, snapshots, _last_snapshot, into_snapshot, :delta}, _opts) do
    # Reduce all deltas in timestamp order. Start from the canonical empty
    # state so every field the reducer might touch is pre-populated — in
    # particular fields like `:create_table_options` that `apply_op` updates
    # via map-update syntax (`%{state | key: v}`), which would raise KeyError
    # on a minimal map.
    initial_state =
      AshPostgres.MigrationGenerator.Reducer.empty_state(%{
        table: nil,
        schema: nil,
        repo: nil
      })

    state =
      snapshots
      |> Enum.sort()
      |> Enum.reduce(initial_state, fn file, acc ->
        {:ok, decoded} =
          case File.read(file) do
            {:ok, contents} -> {:ok, Codec.decode_delta(contents)}
            err -> err
          end

        # Hydrate table/schema/repo context from the first meaningful delta.
        acc = maybe_hydrate_context(acc, decoded.operations)

        Enum.reduce(decoded.operations, acc, fn op, state ->
          try do
            AshPostgres.MigrationGenerator.Reducer.apply_op(state, op)
          catch
            :throw, {:reducer_error, reason} ->
              raise "Failed to squash #{file}: #{reason}"
          end
        end)
      end)

    operations = MigrationGenerator.initial_operations_for_state(state)

    delta_json =
      Codec.encode_delta(operations, %{
        previous_hash: nil,
        resulting_hash: nil,
        migration: nil
      })

    # Remove all files, then write the squashed one.
    Enum.each(snapshots, &File.rm!/1)
    File.write!(into_snapshot, delta_json)
  end

  defp maybe_hydrate_context(state, operations) do
    Enum.reduce(operations, state, fn
      %{table: table, schema: schema} = op, acc when is_binary(table) ->
        acc
        |> Map.put(:table, table)
        |> Map.put(:schema, schema)
        |> then(fn s ->
          case op do
            %_{multitenancy: mt} when is_map(mt) -> Map.put(s, :multitenancy, mt)
            _ -> s
          end
        end)
        |> then(fn s ->
          case op do
            %_{repo: repo} when not is_nil(repo) -> Map.put(s, :repo, repo)
            _ -> s
          end
        end)

      _, acc ->
        acc
    end)
  end

  defp print(%{quiet: true}, _message), do: nil
  defp print(_opts, message), do: Mix.shell().info(message)
end
