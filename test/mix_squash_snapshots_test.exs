# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MixSquashSnapshotsTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration
  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)

    %{
      snapshot_path: Path.join(tmp_dir, "snapshots"),
      migration_path: Path.join(tmp_dir, "migrations")
    }
  end

  defmacrop defposts(mod \\ Post, do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule unquote(mod) do
        use Ash.Resource,
          domain: nil,
          data_layer: AshPostgres.DataLayer

        postgres do
          table "posts"
          repo(AshPostgres.TestRepo)

          custom_indexes do
            # need one without any opts
            index(["id"])
            index(["id"], unique: true, name: "test_unique_index")
          end
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        unquote(body)
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defmacrop defdomain(resources) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule Domain do
        use Ash.Domain

        resources do
          for resource <- unquote(resources) do
            resource(resource)
          end
        end
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defp squash_snapshots(snapshot_path, args) do
    args = ["--snapshot-path", snapshot_path] ++ args
    Mix.Task.rerun("ash_postgres.squash_snapshots", args)
  end

  defp list_snapshots(snapshot_path) do
    Path.wildcard("#{snapshot_path}/**/[0-9]*.json")
  end

  describe "with two snapshots to squash" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defposts do
        identities do
          identity(:title, [:title])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defposts do
        identities do
          identity(:title, [:title])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:name, :string, allow_nil?: false, public?: true)
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "runs without flags", %{snapshot_path: snapshot_path} do
      [_first_snapshot, last_snapshot] = list_snapshots(snapshot_path) |> Enum.sort()
      squash_snapshots(snapshot_path, [])
      assert [^last_snapshot] = list_snapshots(snapshot_path)
    end

    test "runs with `--check`", %{snapshot_path: snapshot_path} do
      prev_snapshots = list_snapshots(snapshot_path)
      assert catch_exit(squash_snapshots(snapshot_path, ["--check"])) == {:shutdown, 1}
      assert prev_snapshots == list_snapshots(snapshot_path)
    end

    test "runs with `--dry-run`", %{snapshot_path: snapshot_path} do
      prev_snapshots = list_snapshots(snapshot_path)
      squash_snapshots(snapshot_path, ["--dry-run"])
      assert prev_snapshots == list_snapshots(snapshot_path)
    end

    test "runs with `--into last`", %{snapshot_path: snapshot_path} do
      [_first_snapshot, last_snapshot] = list_snapshots(snapshot_path) |> Enum.sort()
      squash_snapshots(snapshot_path, ["--into", "last"])
      assert [^last_snapshot] = list_snapshots(snapshot_path)
    end

    test "runs with `--into first`", %{snapshot_path: snapshot_path} do
      [first_snapshot, _last_snapshot] = list_snapshots(snapshot_path) |> Enum.sort()
      squash_snapshots(snapshot_path, ["--into", "first"])
      assert [^first_snapshot] = list_snapshots(snapshot_path)
    end

    test "runs with `--into zero`", %{snapshot_path: snapshot_path} do
      squash_snapshots(snapshot_path, ["--into", "zero"])

      assert [snapshot] = list_snapshots(snapshot_path)
      assert snapshot == "#{snapshot_path}/test_repo/posts/00000000000000.json"
    end
  end

  describe "with one snapshot to squash" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defposts do
        identities do
          identity(:title, [:title])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "runs with `--check`", %{snapshot_path: snapshot_path} do
      prev_snapshots = list_snapshots(snapshot_path)
      squash_snapshots(snapshot_path, ["--check"])
      assert prev_snapshots == list_snapshots(snapshot_path)
    end

    test "runs with `--check --into last`", %{snapshot_path: snapshot_path} do
      prev_snapshots = list_snapshots(snapshot_path)
      squash_snapshots(snapshot_path, ["--check", "--into", "last"])
      assert prev_snapshots == list_snapshots(snapshot_path)
    end

    test "runs with `--check --into first`", %{snapshot_path: snapshot_path} do
      prev_snapshots = list_snapshots(snapshot_path)
      squash_snapshots(snapshot_path, ["--check", "--into", "last"])
      assert prev_snapshots == list_snapshots(snapshot_path)
    end

    test "runs with `--check --into zero`", %{snapshot_path: snapshot_path} do
      prev_snapshots = list_snapshots(snapshot_path)

      assert catch_exit(squash_snapshots(snapshot_path, ["--check", "--into", "zero"])) ==
               {:shutdown, 1}

      assert prev_snapshots == list_snapshots(snapshot_path)
    end
  end
end
