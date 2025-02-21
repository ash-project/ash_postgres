defmodule AshPostgres.MigrationGeneratorTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration

  import ExUnit.CaptureLog

  setup do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)
  end

  defmacrop defresource(mod, do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule unquote(mod) do
        use Ash.Resource,
          domain: nil,
          data_layer: AshPostgres.DataLayer

        unquote(body)
      end

      Code.compiler_options(ignore_module_conflict: false)
    end
  end

  defmacrop defposts(mod \\ Post, do: body) do
    quote do
      defresource unquote(mod) do
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
    end
  end

  defmacrop defcomments(mod \\ Comment, do: body) do
    quote do
      defresource unquote(mod) do
        postgres do
          table "comments"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        unquote(body)
      end
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

  defmacrop defresource(mod, table, do: body) do
    quote do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule unquote(mod) do
        use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: nil

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
          uuid_v7_primary_key(:other_id)
          attribute(:title, :string, public?: true)
          attribute(:second_title, :string, public?: true)
          attribute(:title_with_source, :string, source: :t_w_s, public?: true)
          attribute(:title_with_default, :string, public?: true)
          attribute(:email, Test.Support.Types.Email, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
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

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      # the migration creates the table
      assert file_contents =~ "create table(:posts, primary_key: false) do"

      # the migration sets up the custom_indexes
      assert file_contents =~
               ~S{create index(:posts, ["id"], name: "test_unique_index", unique: true)}

      assert file_contents =~ ~S{create index(:posts, ["id"]}

      # the migration adds the id, with its default
      assert file_contents =~
               ~S[add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true]

      # the migration adds the other_id, with its default
      assert file_contents =~
               ~S[add :other_id, :uuid, null: false, default: fragment("uuid_generate_v7()"), primary_key: true]

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
      assert file_contents =~
               ~S{create unique_index(:posts, [:title], name: "posts_title_index")}

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

          identity_wheres_to_sql(second_title: "(second_title like '%foo%')")

          schema("example")
        end

        identities do
          identity(:title, [:title])

          identity :second_title, [:second_title] do
            nils_distinct?(false)
            where expr(contains(second_title, "foo"))
          end
        end

        attributes do
          uuid_primary_key(:id)
          uuid_v7_primary_key(:other_id)
          attribute(:title, :string, public?: true)
          attribute(:second_title, :string, public?: true)
        end
      end

      defdomain([Post])

      {:ok, _} =
        Ecto.Adapters.SQL.query(
          AshPostgres.TestRepo,
          """
          CREATE SCHEMA IF NOT EXISTS example;
          """
        )

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "the migration sets up resources correctly" do
      # the snapshot exists and contains valid json
      assert File.read!(Path.wildcard("test_snapshots_path/test_repo/example.posts/*.json"))
             |> Jason.decode!(keys: :atoms!)

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      # the migration creates the table
      assert file_contents =~ "create table(:posts, primary_key: false, prefix: \"example\") do"

      # the migration sets up the custom_indexes
      assert file_contents =~
               ~S{create index(:posts, ["id"], name: "test_unique_index", unique: true, prefix: "example")}

      assert file_contents =~ ~S{create index(:posts, ["id"]}

      assert file_contents =~
               ~S{create unique_index(:posts, [:second_title], name: "posts_second_title_index", prefix: "example", nulls_distinct: false, where: "((second_title like '%foo%'))")}

      # the migration adds the id, with its default
      assert file_contents =~
               ~S[add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true]

      # the migration adds the other_id, with its default
      assert file_contents =~
               ~S[add :other_id, :uuid, null: false, default: fragment("uuid_generate_v7()"), primary_key: true]

      # the migration adds other attributes
      assert file_contents =~ ~S[add :title, :text]

      # the migration adds custom attributes
      assert file_contents =~ ~S[add :second_title, :varchar, size: 16]

      # the migration creates unique_indexes based on the identities of the resource
      assert file_contents =~
               ~S{create unique_index(:posts, [:title], name: "posts_title_index", prefix: "example")}
    end
  end

  describe "creating initial snapshots for resources with partitioning" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        postgres do
          partitioning do
            method(:list)
            attribute(:title)
          end
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
        quiet: false,
        format: false
      )

      :ok
    end

    test "the migration sets up resources correctly" do
      # the snapshot exists and contains valid json
      assert File.read!(Path.wildcard("test_snapshots_path/test_repo/posts/*.json"))
             |> Jason.decode!(keys: :atoms!)

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      # the migration creates the table with options specifing how to partition the table
      assert file_contents =~
               ~S{create table(:posts, primary_key: false, options: "PARTITION BY LIST (title)") do}
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
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )
    end

    test "it creates multiple migration files" do
      assert [_, custom_index_migration] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file = File.read!(custom_index_migration)

      assert file =~ ~S[@disable_ddl_transaction true]

      assert file =~ ~S<create index(:posts, [:title], concurrently: true)>
    end
  end

  describe "custom_indexes with `null_distinct: false`" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        postgres do
          custom_indexes do
            index([:uniq_one], nulls_distinct: true)
            index([:uniq_two], nulls_distinct: false)
            index([:uniq_custom_one])
          end
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
        format: false
      )
    end

    test "it adds nulls_distinct option to create index migration" do
      assert [custom_index_migration] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file = File.read!(custom_index_migration)

      assert file =~ ~S<create index(:posts, [:uniq_one])>
      assert file =~ ~S<create index(:posts, [:uniq_two], nulls_distinct: false)>
      assert file =~ ~S<create index(:posts, [:uniq_custom_one])>
    end
  end

  describe "creating follow up migrations with a composite primary key" do
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
          attribute(:title, :string, public?: true, primary_key?: true, allow_nil?: false)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "when removing an element, it recreates the primary key" do
      defposts do
        postgres do
          schema("example")
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file2)

      [up_side, down_side] = String.split(contents, "def down", parts: 2)

      assert up_side =~ ~S[execute("ALTER TABLE \"example.posts\" ADD PRIMARY KEY (id)")]
      assert down_side =~ ~S[execute("ALTER TABLE \"example.posts\" DROP constraint posts_pkey")]
      assert down_side =~ ~S[execute("ALTER TABLE \"example.posts\" ADD PRIMARY KEY (id, title)")]

      defposts do
        postgres do
          schema("example")
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true, primary_key?: true, allow_nil?: false)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, _file2, file3] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file3)

      [up_side, down_side] = String.split(contents, "def down", parts: 2)

      assert up_side =~ ~S[execute("ALTER TABLE \"example.posts\" ADD PRIMARY KEY (id, title)")]
      assert down_side =~ ~S[execute("ALTER TABLE \"example.posts\" ADD PRIMARY KEY (id)")]
    end
  end

  describe "creating a multitenancy resource without composite key, adding it later" do
    setup do
      on_exit(fn ->
        nil
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
        File.rm_rf!("test_tenant_migration_path")
      end)

      :ok
    end

    test "create without composite key, then add extra key" do
      defposts do
        postgres do
          schema("example")
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true, allow_nil?: false)
        end

        multitenancy do
          strategy(:context)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        tenant_migration_path: "test_tenant_migration_path",
        quiet: false,
        format: false
      )

      defposts do
        postgres do
          schema("example")
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true, primary_key?: true, allow_nil?: false)
        end

        multitenancy do
          strategy(:context)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        tenant_migration_path: "test_tenant_migration_path",
        quiet: false,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_tenant_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file2)

      [up_side, down_side] = String.split(contents, "def down", parts: 2)

      assert up_side =~
               ~S[execute("ALTER TABLE \"#{prefix()}\".\"posts\" ADD PRIMARY KEY (id, title)")]

      assert down_side =~
               ~S[execute("ALTER TABLE \"#{prefix()}\".\"posts\" ADD PRIMARY KEY (id)")]
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
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
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
          attribute(:name, :string, allow_nil?: false, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~ ~S[rename table(:posts, prefix: "example"), :title, to: :name]
    end

    test "renaming a field honors additional changes" do
      defposts do
        postgres do
          schema("example")
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, default: "fred", public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~ ~S[rename table(:posts, prefix: "example"), :title, to: :name]
      assert File.read!(file2) =~ ~S[modify :title, :text, null: true, default: nil]
    end
  end

  describe "changing global multitenancy" do
    setup do
      on_exit(fn ->
        File.rm_rf!("test_snapshots_path")
        File.rm_rf!("test_migration_path")
      end)

      defposts do
        identities do
          identity(:title, [:title])
        end

        multitenancy do
          strategy(:attribute)
          attribute(:organization_id)
          global?(false)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:organization_id, :string)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "when changing multitenancy to global, identities aren't rewritten" do
      defposts do
        identities do
          identity(:title, [:title])
        end

        multitenancy do
          strategy(:attribute)
          attribute(:organization_id)
          global?(true)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:organization_id, :string)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))
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
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "when renaming an attribute of an index, it is properly renamed without modifying the attribute" do
      defposts do
        identities do
          identity(:title, [:foobar])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:foobar, :string, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file2)
      refute contents =~ "modify"
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
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[ALTER INDEX posts_title_index RENAME TO titles_r_unique_dawg]
    end

    test "when changing the where clause, it is properly dropped and recreated" do
      defposts do
        postgres do
          identity_wheres_to_sql(title: "title != 'fred' and title != 'george'")
        end

        identities do
          identity(:title, [:title], where: expr(title not in ["fred", "george"]))
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
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert [file_before, _] =
               String.split(
                 File.read!(file2),
                 ~S{create unique_index(:posts, [:title], name: "posts_title_index", where: "(title != 'fred' and title != 'george')")}
               )

      assert file_before =~
               ~S{drop_if_exists unique_index(:posts, [:title], name: "posts_title_index")}
    end

    test "when adding a field, it adds the field" do
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

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :name, :text, null: false]
    end

    test "when renaming a field, it asks if you are renaming it, and renames it if you are" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~ ~S[rename table(:posts), :title, to: :name]
    end

    test "when renaming a field, it asks if you are renaming it, and adds it if you aren't" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, false})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :name, :text, null: false]
    end

    test "when renaming a field, it asks which field you are renaming it to, and renames it if you are" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, public?: true)
          attribute(:subject, :string, allow_nil?: false, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :prompt, "subject"})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      # Up migration
      assert File.read!(file2) =~ ~S[rename table(:posts), :title, to: :subject]

      # Down migration
      assert File.read!(file2) =~ ~S[rename table(:posts), :subject, to: :title]
    end

    test "when renaming a field, it asks which field you are renaming it to, and adds it if you arent" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, public?: true)
          attribute(:subject, :string, allow_nil?: false, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, false})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :subject, :text, null: false]
    end

    test "when multiple schemas apply to the same table, all attributes are added" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:foobar, :string, public?: true)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :foobar, :text]

      assert File.read!(file2) =~
               ~S[add :foobar, :text]
    end

    test "when multiple schemas apply to the same table, all identities are added" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end

        identities do
          identity(:unique_title, [:title])
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end

        identities do
          identity(:unique_name, [:name])
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

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

    test "when concurrent-indexes flag set to true, identities are added in separate migration" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:name, :string, public?: true)
        end

        identities do
          identity(:unique_title, [:title])
          identity(:unique_name, [:name])
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        concurrent_indexes: true,
        format: false
      )

      assert [_file1, _file2, file3] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file3_content = File.read!(file3)

      assert file3_content =~ ~S[@disable_ddl_transaction true]

      assert file3_content =~
               "create unique_index(:posts, [:title], name: \"posts_unique_title_index\")"

      assert file3_content =~
               "create unique_index(:posts, [:name], name: \"posts_unique_name_index\")"
    end

    test "when an attribute exists only on some of the resources that use the same table, it isn't marked as null: false" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:example, :string, allow_nil?: false, public?: true)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

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
          attribute(:id, :integer,
            generated?: true,
            allow_nil?: false,
            primary_key?: true,
            public?: true
          )

          attribute(:views, :integer, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      :ok
    end

    test "when an integer is generated and default nil, it is a bigserial" do
      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

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
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      [domain: Domain]
    end

    test "returns code(1) if snapshots and resources don't fit", %{domain: domain} do
      assert catch_exit(
               AshPostgres.MigrationGenerator.generate(domain,
                 snapshot_path: "test_snapshots_path",
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
          attribute(:title, :string, public?: true)
          attribute(:foobar, :string, public?: true)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end

        relationships do
          belongs_to(:post, Post, public?: true)
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S[references(:posts, column: :id, name: "posts_post_id_fkey", type: :uuid, prefix: "public")]
    end

    test "references are inferred automatically if the attribute has a different type" do
      defposts do
        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
          attribute(:title, :string, public?: true)
          attribute(:foobar, :string, public?: true)
        end
      end

      defposts Post2 do
        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
          attribute(:name, :string, public?: true)
        end

        relationships do
          belongs_to(:post, Post, attribute_type: :string, public?: true)
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S[references(:posts, column: :id, name: "posts_post_id_fkey", type: :text, prefix: "public")]
    end

    test "references allow passing :match_with and :match_type" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:key_id, :uuid, allow_nil?: false, public?: true)
          attribute(:foobar, :string, public?: true)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
          attribute(:related_key_id, :uuid, public?: true)
        end

        relationships do
          belongs_to(:post, Post) do
            public?(true)
          end
        end

        postgres do
          references do
            reference(:post, match_with: [related_key_id: :key_id], match_type: :partial)
          end
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{references(:posts, column: :id, with: [related_key_id: :key_id], match: :partial, name: "posts_post_id_fkey", type: :uuid, prefix: "public")}
    end

    test "references generate related index when index? true" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:key_id, :uuid, allow_nil?: false, public?: true)
          attribute(:foobar, :string, public?: true)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
          attribute(:related_key_id, :uuid, public?: true)
        end

        relationships do
          belongs_to(:post, Post) do
            public?(true)
          end
        end

        postgres do
          references do
            reference(:post, index?: true)
          end
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~ ~S{create index(:posts, [:post_id])}
    end

    test "index generated by index? true also adds column when using attribute multitenancy" do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true, public?: true)
          attribute(:name, :string, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:key_id, :uuid, allow_nil?: false, public?: true)
          attribute(:foobar, :string, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
          attribute(:related_key_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:post, Post) do
            public?(true)
          end

          belongs_to(:org, Org) do
            public?(true)
          end
        end

        postgres do
          references do
            reference(:post, index?: true)
          end
        end
      end

      defdomain([Org, Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~ ~S{create index(:posts, [:org_id, :post_id])}
    end

    test "references merge :match_with and multitenancy attribute" do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true, public?: true)
          attribute(:name, :string, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:secondary_id, :uuid, public?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:key_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defresource UserThing, "user_things" do
        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:related_key_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end

          belongs_to(:user, User, destination_attribute: :secondary_id, public?: true)
        end

        postgres do
          references do
            reference(:user, match_with: [related_key_id: :key_id], match_type: :full)
          end
        end
      end

      defdomain([Org, User, UserThing])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{references(:users, column: :secondary_id, with: [related_key_id: :key_id, org_id: :org_id], match: :full, name: "user_things_user_id_fkey", type: :uuid, prefix: "public")}
    end

    test "identities using `all_tenants?: true` will not have the condition on multitenancy attribtue added" do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:secondary_id, :uuid, public?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:key_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        identities do
          identity(:unique_name, [:name], all_tenants?: true)
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{create unique_index(:users, [:name], name: "users_unique_name_index")}
    end

    test "when modified, the foreign key is dropped before modification" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:foobar, :string, public?: true)
        end
      end

      defposts Post2 do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end

        relationships do
          belongs_to(:post, Post) do
            public?(true)
          end
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
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
          attribute(:name, :string, public?: true)
        end

        relationships do
          belongs_to(:post, Post) do
            public?(true)
          end
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
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
          attribute(:name, :string, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:secondary_id, :uuid, public?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defresource UserThing1, "user_things1" do
        attributes do
          attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end

          belongs_to(:user, User, destination_attribute: :secondary_id, public?: true)
        end
      end

      defresource UserThing2, "user_things2" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end

          belongs_to(:user, User) do
            public?(true)
          end
        end
      end

      defdomain([Org, User, UserThing1, UserThing2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{references(:users, column: :secondary_id, with: [org_id: :org_id], match: :full, name: "user_things1_user_id_fkey", type: :uuid, prefix: "public")}

      assert File.read!(file) =~
               ~S[references(:users, column: :id, name: "user_things2_user_id_fkey", type: :uuid, prefix: "public")]
    end

    test "references on_delete: {:nilify, columns} works with multitenant resources" do
      defresource Tenant, "tenants" do
        attributes do
          uuid_primary_key(:id)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource Group, "groups" do
        attributes do
          uuid_primary_key(:id)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:tenant_id)
        end

        relationships do
          belongs_to(:tenant, Tenant)
        end

        postgres do
          references do
            reference(:tenant, on_delete: :delete)
          end
        end
      end

      defresource Item, "items" do
        attributes do
          uuid_primary_key(:id)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:tenant_id)
        end

        relationships do
          belongs_to(:group, Group)
          belongs_to(:tenant, Tenant)
        end

        postgres do
          references do
            reference(:group,
              match_with: [tenant_id: :tenant_id],
              on_delete: {:nilify, [:group_id]}
            )

            reference(:tenant, on_delete: :delete)
          end
        end
      end

      defdomain([Tenant, Group, Item])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S<references(:groups, column: :id, with: [tenant_id: :tenant_id], name: "items_group_id_fkey", type: :uuid, prefix: "public", on_delete: {:nilify, [:group_id]}>
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
          attribute(:price, :integer, public?: true)
        end

        postgres do
          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: "price > 0")
          end
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
               |> Enum.sort()
               |> Enum.at(0)
               |> File.read!()

      assert file =~
               ~S[create constraint(:posts, :price_must_be_positive, check: "price > 0")]

      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer, public?: true)
        end

        postgres do
          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: "price > 1")
          end
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
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
          attribute(:price, :integer, public?: true)
        end

        postgres do
          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: "price > 0")
          end
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer, public?: true)
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert file =
               "test_migration_path/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
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

      defcomments do
        postgres do
          polymorphic?(true)
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:resource_id, :uuid, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defmodule Post do
        use Ash.Resource,
          domain: nil,
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
            public?: true,
            destination_attribute: :resource_id,
            relationship_context: %{data_layer: %{table: "post_comments"}}
          )

          belongs_to(:best_comment, Comment,
            public?: true,
            destination_attribute: :id,
            relationship_context: %{data_layer: %{table: "post_comments"}}
          )
        end
      end

      defdomain([Post, Comment])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      [domain: Domain]
    end

    test "it uses the relationship's table context if it is set" do
      assert [file] =
               Path.wildcard("test_migration_path/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

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
          attribute(:start_date, :date, default: ~D[2022-04-19], public?: true)
          attribute(:start_time, :time, default: ~T[08:30:45], public?: true)
          attribute(:timestamp, :utc_datetime, default: ~U[2022-02-02 08:30:30Z], public?: true)

          attribute(:timestamp_naive, :naive_datetime,
            default: ~N[2022-02-02 08:30:30],
            public?: true
          )

          attribute(:number, :integer, default: 5, public?: true)
          attribute(:fraction, :float, default: 0.25, public?: true)

          attribute(:decimal, :decimal,
            default: Decimal.new("123.4567890987654321987"),
            public?: true
          )

          attribute(:name, :string, default: "Fred", public?: true)
          attribute(:tag, :atom, default: :value, public?: true)
          attribute(:enabled, :boolean, default: false, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [file1] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

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
          attribute(:product_code, :term, default: {"xyz"}, public?: true)
        end
      end

      defdomain([Post])

      log =
        capture_log(fn ->
          AshPostgres.MigrationGenerator.generate(Domain,
            snapshot_path: "test_snapshots_path",
            migration_path: "test_migration_path",
            quiet: true,
            format: false
          )
        end)

      assert log =~ "`{\"xyz\"}`"

      assert [file1] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

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
          attribute(:title, :string, public?: true)
        end
      end

      defcomments do
        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          belongs_to(:post, Post) do
            public?(true)
          end
        end
      end

      defdomain([Post, Comment])

      AshPostgres.MigrationGenerator.generate(Domain,
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
          attribute(:id, :uuid,
            primary_key?: false,
            default: &Ecto.UUID.generate/0,
            public?: true
          )

          uuid_primary_key(:guid)
          attribute(:title, :string, public?: true)
        end
      end

      defcomments do
        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          belongs_to(:post, Post) do
            public?(true)
          end
        end
      end

      defdomain([Post, Comment])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "test_snapshots_path",
        migration_path: "test_migration_path",
        quiet: true,
        format: false
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("test_migration_path/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

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
