defmodule AshPostgres.MigrationGeneratorTest do
  use AshPostgres.RepoCase, async: false

  defmacrop defposts(do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule Post do
        use Ash.Resource,
          data_layer: AshPostgres.DataLayer

        postgres do
          table "posts"
          repo AshPostgres.TestRepo
        end

        actions do
          read(:read)
          create(:create)
        end

        unquote(body)
      end

      defmodule Api do
        use Ash.Api

        resources do
          resource(Post)
        end
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  test "if the snapshot path doesn't exist, it raises" do
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

    assert_raise Mix.Error, ~r/Could not find snapshots directory/, fn ->
      AshPostgres.Migrator.generate(Api, snapshot_path: "alskjdfhalsdkjfh")
    end
  end

  describe "creating initial snapshots" do
    setup do
      on_exit(fn ->
        "test_snapshots_path/**/*.json"
        |> Path.wildcard()
        |> Enum.each(&File.rm!/1)

        "test_snapshots_path/*"
        |> Path.wildcard()
        |> Enum.each(&File.rmdir!/1)

        "test_migration_path/**/*.exs"
        |> Path.wildcard()
        |> Enum.each(&File.rm!/1)

        "test_migration_path/*"
        |> Path.wildcard()
        |> Enum.each(&File.rmdir!/1)

        if File.exists?("test_snapshots_path") do
          File.rmdir("test_snapshots_path")
        end

        if File.exists?("test_migration_path") do
          File.rmdir("test_migration_path")
        end
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

      Mix.shell(Mix.Shell.Process)

      AshPostgres.Migrator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        init: true,
        quiet: true
      )

      :ok
    end

    test "if the `init` flag is set, the path is created" do
      assert File.exists?("test_snapshots_path")
      assert File.exists?("test_migration_path")
    end

    test "it creates a snapshot for each resource" do
      assert File.exists?(Path.join(["test_snapshots_path", "test_repo", "posts.json"]))
    end

    test "the snapshots can be loaded" do
      assert File.exists?(Path.join(["test_snapshots_path", "test_repo", "posts.json"]))
    end

    test "the snapshots contain valid json" do
      assert File.read!(Path.join(["test_snapshots_path", "test_repo", "posts.json"]))
             |> Jason.decode!(keys: :atoms!)
    end

    test "the migration creates the table" do
      assert [file] = Path.wildcard("test_migration_path/*_create_posts.exs")

      assert File.read!(file) =~ "create table(:posts, primary_key: false) do"
    end

    test "the migration adds the id, with its default" do
      assert [file] = Path.wildcard("test_migration_path/*_create_posts.exs")

      assert File.read!(file) =~
               ~S[add(:id, :binary_id, null: true, default: fragment("uuid_generate_v4()"), primary_key: true]
    end

    test "the migration adds other attributes" do
      assert [file] = Path.wildcard("test_migration_path/*_create_posts.exs")

      assert File.read!(file) =~
               ~S[add(:title, :text, null: true, default: nil, primary_key: false)]
    end

    test "the migration creates unique_indexes based on the identities of the resource" do
      assert [file] = Path.wildcard("test_migration_path/*_create_posts.exs")

      assert File.read!(file) =~
               ~S{create(unique_index(:posts, [:title], name: :posts_title_unique_index))}
    end
  end

  describe "creating follow up migrations" do
    setup do
      on_exit(fn ->
        "test_snapshots_path/**/*.json"
        |> Path.wildcard()
        |> Enum.each(&File.rm!/1)

        "test_snapshots_path/*"
        |> Path.wildcard()
        |> Enum.each(&File.rmdir!/1)

        "test_migration_path/**/*.exs"
        |> Path.wildcard()
        |> Enum.each(&File.rm!/1)

        "test_migration_path/*"
        |> Path.wildcard()
        |> Enum.each(&File.rmdir!/1)

        if File.exists?("test_snapshots_path") do
          File.rmdir("test_snapshots_path")
        end

        if File.exists?("test_migration_path") do
          File.rmdir("test_migration_path")
        end
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

      Mix.shell(Mix.Shell.Process)

      AshPostgres.Migrator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        init: true,
        quiet: true
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

      AshPostgres.Migrator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        init: true,
        quiet: true
      )

      assert [file] = Path.wildcard("test_migration_path/*_update_posts.exs")

      assert File.read!(file) =~
               ~S[add(:name, :text, null: false, default: nil, primary_key: false)]
    end

    test "when renaming a field, it asks if you are renaming it, and renames it if you are" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:name, :string, allow_nil?: false)
        end
      end

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.Migrator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        init: true,
        quiet: true
      )

      assert [file] = Path.wildcard("test_migration_path/*_update_posts.exs")

      assert File.read!(file) =~ ~S[rename(table("posts"), :title, to: :name)]
    end

    test "when renaming a field, it asks if you are renaming it, and adds it if you aren't" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: true, default: &Ecto.UUID.generate/0)
          attribute(:name, :string, allow_nil?: false)
        end
      end

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.Migrator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        init: true,
        quiet: true
      )

      assert [file] = Path.wildcard("test_migration_path/*_update_posts.exs")

      assert File.read!(file) =~ ~S[rename(table("posts"), :title, to: :name)]
    end
  end
end
