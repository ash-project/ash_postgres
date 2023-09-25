defmodule AshPostgres.MigrationGeneratorTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration

  import ExUnit.CaptureLog

  defmacrop defposts(mod \\ Post, do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule unquote(mod) do
        use Ash.Resource,
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

  defmacrop defapi(resources) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule Registry do
        use Ash.Registry

        entries do
          for resource <- unquote(resources) do
            entry(resource)
          end
        end
      end

      defmodule Api do
        use Ash.Api

        resources do
          registry(Registry)
        end
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defmacrop defresource(mod, table, do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule unquote(mod) do
        use Ash.Resource, data_layer: AshPostgres.DataLayer

        postgres do
          table unquote(table)
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        unquote(body)
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
        postgres do
          migration_types(second_title: {:varchar, 16})
          migration_defaults(title_with_default: "\"fred\"")
        end

        identities do
          identity(:title, [:title])
          identity(:thing, [:title, :second_title])
          identity(:thing_with_source, [:title, :title_with_source])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
          attribute(:second_title, :string)
          attribute(:title_with_source, :string, source: :t_w_s)
          attribute(:title_with_default, :string)
          attribute(:email, Test.Support.Types.Email)
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

    test "the migration sets up resources correctly" do
      # the snapshot exists and contains valid json
      assert File.read!(Path.wildcard("test_snapshots_path/test_repo/posts/*.json"))
             |> Jason.decode!(keys: :atoms!)

      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      file_contents = File.read!(file)

      # the migration creates the table
      assert file_contents =~ "create table(:posts, primary_key: false) do"

      # the migration sets up the custom_indexes
      assert file_contents =~
               ~S{create index(:posts, ["id"], name: "test_unique_index", unique: true)}

      assert file_contents =~ ~S{create index(:posts, ["id"]}

      # the migration adds the id, with its default
      assert file_contents =~
               ~S[add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true]

      # the migration adds the id, with its default
      assert file_contents =~
               ~S[add :title_with_default, :text, default: "fred"]

      # the migration adds other attributes
      assert file_contents =~ ~S[add :title, :text]

      # the migration unwraps newtypes
      assert file_contents =~ ~S[add :email, :citext]

      # the migration adds custom attributes
      assert file_contents =~ ~S[add :second_title, :varchar, size: 16]

      # the migration creates unique_indexes based on the identities of the resource
      assert file_contents =~ ~S{create unique_index(:posts, [:title], name: "posts_title_index")}

      # the migration creates unique_indexes based on the identities of the resource
      assert file_contents =~
               ~S{create unique_index(:posts, [:title, :second_title], name: "posts_thing_index")}

      # the migration creates unique_indexes using the `source` on the attributes of the identity on the resource
      assert file_contents =~
               ~S{create unique_index(:posts, [:title, :t_w_s], name: "posts_thing_with_source_index")}
    end
  end

  describe "creating initial snapshots for resources with a schema" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        postgres do
          migration_types(second_title: {:varchar, 16})
          schema("example")
        end

        identities do
          identity(:title, [:title])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
          attribute(:second_title, :string)
        end
      end

      defapi([Post])

      Mix.shell(Mix.Shell.Process)

      {:ok, _} =
        Ecto.Adapters.SQL.query(
          AshPostgres.TestRepo,
          """
          CREATE SCHEMA IF NOT EXISTS example;
          """
        )

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "the migration sets up resources correctly" do
      # the snapshot exists and contains valid json
      assert File.read!(Path.wildcard("test_snapshots_path/test_repo/posts/*.json"))
             |> Jason.decode!(keys: :atoms!)

      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      file_contents = File.read!(file)

      # the migration creates the table
      assert file_contents =~ "create table(:posts, primary_key: false, prefix: \"example\") do"

      # the migration sets up the custom_indexes
      assert file_contents =~
               ~S{create index(:posts, ["id"], name: "test_unique_index", unique: true, prefix: "example")}

      assert file_contents =~ ~S{create index(:posts, ["id"]}

      # the migration adds the id, with its default
      assert file_contents =~
               ~S[add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true]

      # the migration adds other attributes
      assert file_contents =~ ~S[add :title, :text]

      # the migration adds custom attributes
      assert file_contents =~ ~S[add :second_title, :varchar, size: 16]

      # the migration creates unique_indexes based on the identities of the resource
      assert file_contents =~
               ~S{create unique_index(:posts, [:title], name: "posts_title_index", prefix: "example")}
    end
  end

  describe "custom_indexes with `concurrently: true`" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        postgres do
          custom_indexes do
            # need one without any opts
            index([:title], concurrently: true)
          end
        end

        attributes do
          uuid_primary_key(:id)
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
    end

    test "it creates multiple migration files" do
      assert [_, custom_index_migration] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      file = File.read!(custom_index_migration)

      assert file =~ ~S[@disable_ddl_transaction true]

      assert file =~ ~S<create index(:posts, ["title"], concurrently: true)>
    end
  end

  describe "creating follow up migrations with a schema" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        postgres do
          schema("example")
        end

        attributes do
          uuid_primary_key(:id)
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

    test "when renaming a field, it asks if you are renaming it, and renames it if you are" do
      defposts do
        postgres do
          schema("example")
        end

        attributes do
          uuid_primary_key(:id)
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

      assert File.read!(file2) =~ ~S[rename table(:posts, prefix: "example"), :title, to: :name]
    end
  end

  describe "creating follow up migrations" do
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

    test "when renaming an index, it is properly renamed" do
      defposts do
        postgres do
          identity_index_names(title: "titles_r_unique_dawg")
        end

        identities do
          identity(:title, [:title])
        end

        attributes do
          uuid_primary_key(:id)
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
               ~S[ALTER INDEX posts_title_index RENAME TO titles_r_unique_dawg]
    end

    test "when adding a field, it adds the field" do
      defposts do
        identities do
          identity(:title, [:title])
        end

        attributes do
          uuid_primary_key(:id)
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
               ~S[add :name, :text, null: false]
    end

    test "when renaming a field, it asks if you are renaming it, and renames it if you are" do
      defposts do
        attributes do
          uuid_primary_key(:id)
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
          uuid_primary_key(:id)
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
               ~S[add :name, :text, null: false]
    end

    test "when renaming a field, it asks which field you are renaming it to, and renames it if you are" do
      defposts do
        attributes do
          uuid_primary_key(:id)
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

      # Up migration
      assert File.read!(file2) =~ ~S[rename table(:posts), :title, to: :subject]

      # Down migration
      assert File.read!(file2) =~ ~S[rename table(:posts), :subject, to: :title]
    end

    test "when renaming a field, it asks which field you are renaming it to, and adds it if you arent" do
      defposts do
        attributes do
          uuid_primary_key(:id)
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
               ~S[add :subject, :text, null: false]
    end

    test "when multiple schemas apply to the same table, all attributes are added" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
          attribute(:foobar, :string)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
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
               ~S[add :foobar, :text]

      assert File.read!(file2) =~
               ~S[add :foobar, :text]
    end

    test "when multiple schemas apply to the same table, all identities are added" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
        end

        identities do
          identity(:unique_title, [:title])
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string)
        end

        identities do
          identity(:unique_name, [:name])
        end
      end

      defapi([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      file1_content = File.read!(file1)

      assert file1_content =~
               "create unique_index(:posts, [:title], name: \"posts_title_index\")"

      file2_content = File.read!(file2)

      assert file2_content =~
               "drop_if_exists unique_index(:posts, [:title], name: \"posts_title_index\")"

      assert file2_content =~
               "create unique_index(:posts, [:name], name: \"posts_unique_name_index\")"

      assert file2_content =~
               "create unique_index(:posts, [:title], name: \"posts_unique_title_index\")"
    end

    test "when an attribute exists only on some of the resources that use the same table, it isn't marked as null: false" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
          attribute(:example, :string, allow_nil?: false)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
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
               ~S[add :example, :text] <> "\n"

      refute File.read!(file2) =~ ~S[null: false]
    end
  end

  describe "auto incrementing integer, when generated" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        attributes do
          attribute(:id, :integer, generated?: true, allow_nil?: false, primary_key?: true)
          attribute(:views, :integer)
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

    test "when an integer is generated and default nil, it is a bigserial" do
      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S[add :id, :bigserial, null: false, primary_key: true]

      assert File.read!(file) =~
               ~S[add :views, :bigint]
    end
  end

  describe "--check option" do
    setup do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
        end
      end

      defapi([Post])

      [api: Api]
    end

    test "returns code(1) if snapshots and resources don't fit", %{api: api} do
      assert catch_exit(
               AshPostgres.MigrationGenerator.generate(api,
                 snapshot_path: "test_snapshot_path",
                 migration_path: "test_migration_path",
                 check: true
               )
             ) == {:shutdown, 1}

      refute File.exists?(Path.wildcard("test_migration_path2/**/*_migrate_resources*.exs"))
      refute File.exists?(Path.wildcard("test_snapshots_path2/test_repo/posts/*.json"))
    end
  end

  describe "references" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)
    end

    test "references are inferred automatically" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
          attribute(:foobar, :string)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string)
        end

        relationships do
          belongs_to(:post, Post)
        end
      end

      defapi([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S[references(:posts, column: :id, name: "posts_post_id_fkey", type: :uuid, prefix: "public")]
    end

    test "references are inferred automatically if the attribute has a different type" do
      defposts do
        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false)
          attribute(:title, :string)
          attribute(:foobar, :string)
        end
      end

      defposts Post2 do
        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false)
          attribute(:name, :string)
        end

        relationships do
          belongs_to(:post, Post, attribute_type: :string)
        end
      end

      defapi([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S[references(:posts, column: :id, name: "posts_post_id_fkey", type: :text, prefix: "public")]
    end

    test "when modified, the foreign key is dropped before modification" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
          attribute(:foobar, :string)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string)
        end

        relationships do
          belongs_to(:post, Post)
        end
      end

      defapi([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      defposts Post2 do
        postgres do
          references do
            reference(:post, name: "special_post_fkey", on_delete: :delete, on_update: :update)
          end
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string)
        end

        relationships do
          belongs_to(:post, Post)
        end
      end

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.sort()
               |> Enum.at(1)
               |> File.read!()

      assert file =~
               ~S[references(:posts, column: :id, name: "special_post_fkey", type: :uuid, prefix: "public", on_delete: :delete_all, on_update: :update_all)]

      assert file =~ ~S[drop constraint(:posts, "posts_post_id_fkey")]

      assert [_, down_code] = String.split(file, "def down do")

      assert [_, after_drop] =
               String.split(down_code, "drop constraint(:posts, \"special_post_fkey\")")

      assert after_drop =~ ~S[references(:posts]
    end

    test "references with added only when needed on multitenant resources" do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:secondary_id, :uuid)
          attribute(:name, :string)
          attribute(:org_id, :uuid)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org)
        end
      end

      defresource UserThing1, "user_things1" do
        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false)
          attribute(:name, :string)
          attribute(:org_id, :uuid)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org)
          belongs_to(:user, User, destination_attribute: :secondary_id)
        end
      end

      defresource UserThing2, "user_things2" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org)
          belongs_to(:user, User)
        end
      end

      defapi([Org, User, UserThing1, UserThing2])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S[references(:users, column: :secondary_id, with: [org_id: :org_id\], match: :full, name: "user_things1_user_id_fkey", type: :uuid, prefix: "public")]
      assert File.read!(file) =~
               ~S[references(:users, column: :id, name: "user_things2_user_id_fkey", type: :uuid, prefix: "public")]
    end
  end

  describe "check constraints" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)
    end

    test "when added, the constraint is created" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer)
        end

        postgres do
          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: "price > 0")
          end
        end
      end

      defapi([Post])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.sort()
               |> Enum.at(0)
               |> File.read!()

      assert file =~
               ~S[create constraint(:posts, :price_must_be_positive, check: "price > 0")]

      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer)
        end

        postgres do
          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: "price > 1")
          end
        end
      end

      defapi([Post])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.sort()
               |> Enum.at(1)
               |> File.read!()

      assert [_, down] = String.split(file, "def down do")

      assert [_, remaining] =
               String.split(down, "drop_if_exists constraint(:posts, :price_must_be_positive)")

      assert remaining =~
               ~S[create constraint(:posts, :price_must_be_positive, check: "price > 0")]
    end

    test "when removed, the constraint is dropped before modification" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer)
        end

        postgres do
          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: "price > 0")
          end
        end
      end

      defapi([Post])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer)
        end
      end

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.sort()
               |> Enum.at(1)

      assert File.read!(file) =~
               ~S[drop_if_exists constraint(:posts, :price_must_be_positive)]
    end
  end

  describe "polymorphic resources" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defmodule Comment do
        use Ash.Resource,
          data_layer: AshPostgres.DataLayer

        postgres do
          polymorphic?(true)
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:resource_id, :uuid)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defmodule Post do
        use Ash.Resource,
          data_layer: AshPostgres.DataLayer

        postgres do
          table "posts"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          has_many(:comments, Comment,
            destination_attribute: :resource_id,
            relationship_context: %{data_layer: %{table: "post_comments"}}
          )

          belongs_to(:best_comment, Comment,
            destination_attribute: :id,
            relationship_context: %{data_layer: %{table: "post_comments"}}
          )
        end
      end

      defapi([Post, Comment])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      [api: Api]
    end

    test "it uses the relationship's table context if it is set" do
      assert [file] = Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")

      assert File.read!(file) =~
               ~S[references(:post_comments, column: :id, name: "posts_best_comment_id_fkey", type: :uuid, prefix: "public")]
    end
  end

  describe "default values" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)
    end

    test "when default value is specified that implements EctoMigrationDefault" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:start_date, :date, default: ~D[2022-04-19])
          attribute(:start_time, :time, default: ~T[08:30:45])
          attribute(:timestamp, :utc_datetime, default: ~U[2022-02-02 08:30:30Z])
          attribute(:timestamp_naive, :naive_datetime, default: ~N[2022-02-02 08:30:30])
          attribute(:number, :integer, default: 5)
          attribute(:fraction, :float, default: 0.25)
          attribute(:decimal, :decimal, default: Decimal.new("123.4567890987654321987"))
          attribute(:name, :string, default: "Fred")
          attribute(:tag, :atom, default: :value)
          attribute(:enabled, :boolean, default: false)
        end
      end

      defapi([Post])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file1] = Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      file = File.read!(file1)

      assert file =~
               ~S[add :start_date, :date, default: fragment("'2022-04-19'")]

      assert file =~
               ~S[add :start_time, :time, default: fragment("'08:30:45'")]

      assert file =~
               ~S[add :timestamp, :utc_datetime, default: fragment("'2022-02-02 08:30:30Z'")]

      assert file =~
               ~S[add :timestamp_naive, :naive_datetime, default: fragment("'2022-02-02 08:30:30'")]

      assert file =~
               ~S[add :number, :bigint, default: 5]

      assert file =~
               ~S[add :fraction, :float, default: 0.25]

      assert file =~
               ~S[add :decimal, :decimal, default: "123.4567890987654321987"]

      assert file =~
               ~S[add :name, :text, default: "Fred"]

      assert file =~
               ~S[add :tag, :text, default: "value"]

      assert file =~
               ~S[add :enabled, :boolean, default: false]
    end

    test "when default value is specified that does not implement EctoMigrationDefault" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:product_code, :term, default: {"xyz"})
        end
      end

      defapi([Post])

      log =
        capture_log(fn ->
          AshPostgres.MigrationGenerator.generate(Api,
            snapshot_path: "test_snapshots_path",
            migration_path: "test_migration_path",
            quiet: true,
            format: false
          )
        end)

      assert log =~ "`{\"xyz\"}`"

      assert [file1] = Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      file = File.read!(file1)

      assert file =~
               ~S[add :product_code, :binary]
    end
  end

  describe "follow up with references" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string)
        end
      end

      defmodule Comment do
        use Ash.Resource,
          data_layer: AshPostgres.DataLayer

        postgres do
          table "comments"
          repo AshPostgres.TestRepo
        end

        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          belongs_to(:post, Post)
        end
      end

      defapi([Post, Comment])

      Mix.shell(Mix.Shell.Process)

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "when changing the primary key, it changes properly" do
      defposts do
        attributes do
          attribute(:id, :uuid, primary_key?: false, default: &Ecto.UUID.generate/0)
          uuid_primary_key(:guid)
          attribute(:title, :string)
        end
      end

      defmodule Comment do
        use Ash.Resource,
          data_layer: AshPostgres.DataLayer

        postgres do
          table "comments"
          repo AshPostgres.TestRepo
        end

        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          belongs_to(:post, Post)
        end
      end

      defapi([Post, Comment])

      AshPostgres.MigrationGenerator.generate(Api,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))

      file = File.read!(file2)

      assert [before_index_drop, after_index_drop] =
               String.split(file, ~S[drop constraint("posts", "posts_pkey")], parts: 2)

      assert before_index_drop =~ ~S[drop constraint(:comments, "comments_post_id_fkey")]

      assert after_index_drop =~ ~S[modify :id, :uuid, null: true, primary_key: false]

      assert after_index_drop =~
               ~S[modify :post_id, references(:posts, column: :id, name: "comments_post_id_fkey", type: :uuid, prefix: "public")]
    end
  end
end
