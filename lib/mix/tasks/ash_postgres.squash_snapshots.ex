defmodule Mix.Tasks.AshPostgres.SquashSnapshots do
  use Mix.Task

  @shortdoc "Cleans snapshots folder, leaving only one snapshot per resource"

  @switches [
    into: :string,
    snapshot_path: :string,
    quiet: :boolean,
    dry_run: :boolean,
    check: :boolean
  ]

  @moduledoc """
  Cleans snapshots folder, leaving only one snapshot per resource.

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
  * `--quiet` - no messages will not be printed.
  * `--dry-run` - no files are touched, instead prints folders that have snapshots to squash.
  * `--check` - no files are touched, instead returns an exit(1) code if there are snapshots to squash.
  """

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
      |> Enum.filter(&String.match?(Path.basename(&1), ~r/^\d{14}\.json$/))
      |> Enum.group_by(&Path.dirname(&1))
      |> Enum.reduce([], fn {folder, snapshots}, squashable ->
        last_snapshot = Enum.max(snapshots)

        into_snapshot =
          case opts.into do
            :last -> last_snapshot
            :first -> Enum.min(snapshots)
            :zero -> Path.join(folder, "00000000000000.json")
          end

        if length(snapshots) > 1 or last_snapshot != into_snapshot do
          [{folder, snapshots, last_snapshot, into_snapshot} | squashable]
        else
          squashable
        end
      end)
      |> Enum.reverse()

    if Enum.empty?(squashable) do
      print(opts, "No snapshots to squash.")
    else
      if opts.dry_run do
        print(opts, "Snapshots in following folders would have been squashed in non-dry run:")
        print(opts, Enum.map_join(squashable, "\n", fn {folder, _, _, _} -> folder end))

        if opts.check do
          exit({:shutdown, 1})
        end
      end

      if opts.check do
        print(opts, """
        Snapshots would have been squashed, but the --check flag was provided.

        To see what snapshots would have been squashed, run with the --dry-run
        flag. To squash those snapshots, run without either flag.
        """)

        exit({:shutdown, 1})
      end

      if not opts.dry_run do
        for {_folder, snapshots, last_snapshot, into_snapshot} <- squashable do
          for snapshot <- snapshots, snapshot != last_snapshot do
            File.rm!(snapshot)
          end

          if last_snapshot != into_snapshot do
            File.rename!(last_snapshot, into_snapshot)
          end
        end
      end
    end
  end

  defp print(%{quiet: true}, _message), do: nil
  defp print(_opts, message), do: Mix.shell().info(message)
end
