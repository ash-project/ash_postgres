defmodule AshPostgres.MigrationGeneratorTest do
  use AshPostgres.RepoCase, async: false

  defmacrop defposts(mod \\ Post, do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule unquote(mod) do
        use Ash.Resource,
          data_layer: AshPostgres.DataLayer

        postgres do
          table "posts"
          repo(AshPostgres.TestRepo)
        end

        actions do
          read(:read)
          create(:create)
        end

        unquote(body)
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defmacrop defapi(resources) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule Api do
        use Ash.Api

        resources do
          for resource <- unquote(resources) do
            resource(resource)
          end
        end
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  describe "creating initial snapshots" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        resource do
          identities do
            identity(:title, [:title])
          end
        end

        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:title, :string)
        end
      end

      defapi([Post])

      Mix.shell(Mix.Shell.Process)

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "it creates a snapshot for each resource" do
      assert File.exists?(Path.wildcard("test_snapshots_path/test_repo/*_posts.json"))
      assert File.exists?(Path.join(["test_snapshots_path", "test_repo", "posts.version.json"]))
    end

    test "the snapshots can be loaded" do
      assert File.exists?(Path.wildcard("test_snapshots_path/test_repo/*_posts.json"))
      assert File.exists?(Path.join(["test_snapshots_path", "test_repo", "posts.version.json"]))
    end

    test "the snapshots contain valid json" do
      assert File.exists?(Path.join(["test_snapshots_path", "test_repo", "posts.version.json"]))
      assert File.read!(Path.wildcard("test_snapshots_path/test_repo/*_posts.json"))
             |> Jason.decode!(keys: :atoms!)

      version_file_content =
        File.read!(Path.join(["test_snapshots_path", "test_repo", "posts.version.json"]))
        |> Jason.decode!(keys: :atoms!)

      assert Map.get(version_file_content, :latest_version, nil) != nil
    end

    test "the migration creates the table" do
      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~ "create table(:posts, primary_key: false) do"
    end

    test "the migration adds the id, with its default" do
      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S[add :id, :binary_id, null: true, default: fragment("uuid_generate_v4()"), primary_key: true]
    end

    test "the migration adds other attributes" do
      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S[add :title, :text, null: true, default: nil, primary_key: false]
    end

    test "the migration creates unique_indexes based on the identities of the resource" do
      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S{create unique_index(:posts, [:title], name: "posts_title_unique_index")}
    end
  end

  describe "creating follow up migrations" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        resource do
          identities do
            identity(:title, [:title])
          end
        end

        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:title, :string)
        end
      end

      defapi([Post])

      Mix.shell(Mix.Shell.Process)

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "when adding a field, it adds the field" do
      defposts do
        resource do
          identities do
            identity(:title, [:title])
          end
        end

        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:title, :string)
          attribute(:name, :string, allow_nil?: false)
        end
      end

      defapi([Post])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      assert File.read!(file2) =~
               ~S[add :name, :text, null: false, default: nil, primary_key: false]
    end

    test "when renaming a field, it asks if you are renaming it, and renames it if you are" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:name, :string, allow_nil?: false)
        end
      end

      defapi([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      assert File.read!(file2) =~ ~S[rename table(:posts), :title, to: :name]
    end

    test "when renaming a field, it asks if you are renaming it, and adds it if you aren't" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:name, :string, allow_nil?: false)
        end
      end

      defapi([Post])

      send(self(), {:mix_shell_input, :yes?, false})

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      assert File.read!(file2) =~
               ~S[add :name, :text, null: false, default: nil, primary_key: false]
    end

    test "when renaming a field, it asks which field you are renaming it to, and renames it if you are" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:name, :string, allow_nil?: false)
          attribute(:subject, :string, allow_nil?: false)
        end
      end

      defapi([Post])

      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :prompt, "subject"})

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      assert File.read!(file2) =~ ~S[rename table(:posts), :title, to: :subject]
    end

    test "when renaming a field, it asks which field you are renaming it to, and adds it if you arent" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:name, :string, allow_nil?: false)
          attribute(:subject, :string, allow_nil?: false)
        end
      end

      defapi([Post])

      send(self(), {:mix_shell_input, :yes?, false})

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      assert File.read!(file2) =~
               ~S[add :subject, :text, null: false, default: nil, primary_key: false]
    end

    test "when changing the primary key, it changes properly" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: false, default: &Ecto.UUID.generate/0)
          attribute(:guid, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:title, :string)
        end
      end

      defapi([Post])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      assert File.read!(file2) =~
               ~S[add :guid, :binary_id, null: true, default: fragment("uuid_generate_v4()"), primary_key: true]
    end

    test "when multiple schemas apply to the same table, all attributes are added" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:title, :string)
          attribute(:foobar, :string)
        end
      end

      defposts Post2 do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:name, :string)
        end
      end

      defapi([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      assert File.read!(file2) =~
               ~S[add :foobar, :text, null: true, default: nil, primary_key: false]

      assert File.read!(file2) =~
               ~S[add :foobar, :text, null: true, default: nil, primary_key: false]
    end
  end
end
