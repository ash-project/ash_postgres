# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshPostgres.MigrateSnapshots do
  @moduledoc """
  Converts legacy full-state resource snapshots into the new delta format.

  Each existing snapshot directory (e.g. `priv/resource_snapshots/my_repo/posts/`)
  is rewritten to contain a single v2 delta file whose operations reconstruct
  the full current state from empty. The legacy full-state files are moved to
  `priv/resource_snapshots/.legacy_backup/<timestamp>/` unless `--keep-legacy`
  is passed.

  This task is a prerequisite for opting into the `:delta` snapshot format on a
  repo with existing snapshots:

      defmodule MyApp.Repo do
        use AshPostgres.Repo,
          otp_app: :my_app,
          snapshot_format: :delta
      end

  Running the task is idempotent: directories whose newest file is already a
  v2 delta are skipped.

  ## Options

  * `--snapshot-path` - custom snapshot directory (defaults to `priv/resource_snapshots`)
  * `--dry-run`       - print what would happen without touching disk
  * `--keep-legacy`   - preserve legacy files in place alongside the new delta
  * `--quiet`         - suppress informational output
  """

  use Mix.Task

  alias AshPostgres.MigrationGenerator
  alias AshPostgres.MigrationGenerator.Operation.Codec

  @shortdoc "Convert legacy full-state snapshots to v2 delta format"

  @switches [
    snapshot_path: :string,
    dry_run: :boolean,
    keep_legacy: :boolean,
    quiet: :boolean
  ]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches)

    opts =
      opts
      |> Map.new()
      |> Map.put_new(:snapshot_path, "priv/resource_snapshots")
      |> Map.put_new(:dry_run, false)
      |> Map.put_new(:keep_legacy, false)
      |> Map.put_new(:quiet, false)

    base = opts.snapshot_path

    if File.dir?(base) do
      backup_stamp =
        DateTime.utc_now()
        |> DateTime.to_iso8601(:basic)
        |> String.replace("Z", "")

      case find_legacy_directories(base) do
        [] ->
          print(
            opts,
            "No legacy snapshots to migrate — all resources already use the delta format."
          )

        dirs ->
          Enum.each(dirs, fn {_dir, all_files, legacy_files} ->
            migrate_directory(all_files, legacy_files, base, backup_stamp, opts)
          end)

          print(opts, "Migration complete.")
      end
    else
      print(opts, "Snapshot directory #{base} does not exist; nothing to migrate.")
      :ok
    end
  end

  # Returns `[{dir, all_files, legacy_files}]` for every directory containing
  # at least one non-v2 file. Each file is read exactly once: the contents are
  # inspected here to classify, and `migrate_directory/6` then uses the
  # pre-classified list without re-reading.
  defp find_legacy_directories(base) do
    base
    |> Path.join("**/*.json")
    |> Path.wildcard()
    |> Enum.reject(&String.contains?(&1, ".legacy_backup"))
    |> Enum.filter(&MigrationGenerator.snapshot_filename?(Path.basename(&1)))
    |> Enum.group_by(&Path.dirname/1)
    |> Enum.reduce([], fn {dir, files}, acc ->
      files = Enum.sort(files)
      legacy_files = Enum.reject(files, &v2?/1)

      if legacy_files == [] do
        acc
      else
        [{dir, files, legacy_files} | acc]
      end
    end)
    |> Enum.sort_by(fn {dir, _, _} -> dir end)
  end

  defp v2?(path) do
    case File.read(path) do
      {:ok, contents} -> Codec.delta?(contents)
      _ -> false
    end
  end

  defp migrate_directory(all_files, legacy_files, base, backup_stamp, opts) do
    latest_path = List.last(all_files)

    if opts.dry_run do
      print(opts, "DRY   would convert #{latest_path} into a v2 delta at #{latest_path}")
    else
      full_state = latest_path |> File.read!() |> Codec.decode_full_state()
      operations = MigrationGenerator.initial_operations_for_state(full_state)

      delta_json =
        Codec.encode_delta(operations, %{
          previous_hash: nil,
          resulting_hash: Map.get(full_state, :hash),
          migration: nil
        })

      File.write!(latest_path, delta_json)

      if !opts.keep_legacy do
        Enum.each(legacy_files, fn path ->
          if path != latest_path, do: move_to_backup(path, base, backup_stamp)
        end)
      end

      print(opts, "DONE  #{latest_path}")
    end

    :ok
  end

  defp move_to_backup(path, base, stamp) do
    relative = Path.relative_to(path, base)
    target = Path.join([base, ".legacy_backup", stamp, relative])
    File.mkdir_p!(Path.dirname(target))
    File.rename!(path, target)
  end

  defp print(%{quiet: true}, _), do: :ok
  defp print(_opts, message), do: Mix.shell().info(message)
end
