defmodule AshPostgres.MixSquashSnapshotsTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration

  setup do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)
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

  def squash_snapshots(args) do
    args = ["--snapshot-path", "test_snapshots_path"] ++ args
    Mix.Task.rerun("ash_postgres.squash_snapshots", args)
  end

  def list_snapshots do
    Path.wildcard("test_snapshots_path/**/[0-9]*.json")
  end

  describe "with two snapshots to squash" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

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
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
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
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "runs without flags" do
      [_first_snapshot, last_snapshot] = list_snapshots() |> Enum.sort()
      squash_snapshots([])
      assert [^last_snapshot] = list_snapshots()
    end

    test "runs with `--check`" do
      prev_snapshots = list_snapshots()
      assert catch_exit(squash_snapshots(["--check"])) == {:shutdown, 1}
      assert prev_snapshots == list_snapshots()
    end

    test "runs with `--dry-run`" do
      prev_snapshots = list_snapshots()
      squash_snapshots(["--dry-run"])
      assert prev_snapshots == list_snapshots()
    end

    test "runs with `--into last`" do
      [_first_snapshot, last_snapshot] = list_snapshots() |> Enum.sort()
      squash_snapshots(["--into", "last"])
      assert [^last_snapshot] = list_snapshots()
    end

    test "runs with `--into first`" do
      [first_snapshot, _last_snapshot] = list_snapshots() |> Enum.sort()
      squash_snapshots(["--into", "first"])
      assert [^first_snapshot] = list_snapshots()
    end

    test "runs with `--into zero`" do
      squash_snapshots(["--into", "zero"])
      assert ["test_snapshots_path/test_repo/posts/00000000000000.json"] = list_snapshots()
    end
  end

  describe "with one snapshot to squash" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

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
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "runs with `--check`" do
      prev_snapshots = list_snapshots()
      squash_snapshots(["--check"])
      assert prev_snapshots == list_snapshots()
    end

    test "runs with `--check --into last`" do
      prev_snapshots = list_snapshots()
      squash_snapshots(["--check", "--into", "last"])
      assert prev_snapshots == list_snapshots()
    end

    test "runs with `--check --into first`" do
      prev_snapshots = list_snapshots()
      squash_snapshots(["--check", "--into", "last"])
      assert prev_snapshots == list_snapshots()
    end

    test "runs with `--check --into zero`" do
      prev_snapshots = list_snapshots()
      assert catch_exit(squash_snapshots(["--check", "--into", "zero"])) == {:shutdown, 1}
      assert prev_snapshots == list_snapshots()
    end
  end
end
