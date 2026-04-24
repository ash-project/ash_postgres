# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationGeneratorTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration
  @moduletag :tmp_dir

  import ExUnit.CaptureLog

  setup %{tmp_dir: tmp_dir} do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)

    %{
      snapshot_path: Path.join(tmp_dir, "snapshots"),
      migration_path: Path.join(tmp_dir, "migrations"),
      tenant_migration_path: Path.join(tmp_dir, "tenant_migrations")
    }
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

  defp position_of_substring(string, substring) do
    case :binary.match(string, substring) do
      {pos, _len} -> pos
      :nomatch -> nil
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

  describe "empty resources" do
    setup do
      :ok
    end

    test "empty resource does not generate migration files", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource EmptyPost, "empty_posts" do
        resource do
          require_primary_key?(false)
        end

        actions do
          defaults([:read, :create])
        end
      end

      defdomain([EmptyPost])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: false,
        format: false,
        auto_name: true
      )

      migration_files =
        Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))

      assert migration_files == []

      snapshot_files =
        Path.wildcard("#{snapshot_path}/**/*.json")
        |> Enum.reject(&String.contains?(&1, "extensions"))

      assert snapshot_files == []
    end

    test "resource with only primary key generates migration", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource PostWithId, "posts_with_id" do
        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([PostWithId])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: false,
        format: false,
        auto_name: true
      )

      migration_files =
        Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))

      assert length(migration_files) == 1

      snapshot_files =
        Path.wildcard("#{snapshot_path}/**/*.json")
        |> Enum.reject(&String.contains?(&1, "extensions"))

      assert length(snapshot_files) == 1
    end
  end

  describe "get_operations_from_snapshots" do
    test "explicit fk attribute order does not change create table emission" do
      # This also reproduces if a non-identity attribute like :note appears between
      # :post_id and the identity key (:title), but this test keeps the minimal case.
      defposts do
        attributes do
          uuid_primary_key(:id)
        end
      end

      defresource CommentPostIdBeforeTitle, "comments_post_id_before_title" do
        attributes do
          uuid_primary_key(:id)
          attribute(:post_id, :uuid, allow_nil?: false, public?: true)
          attribute(:title, :string, public?: true)
        end

        identities do
          identity(:uniq_title, [:title])
        end

        relationships do
          belongs_to(:post, Post) do
            source_attribute(:post_id)
            destination_attribute(:id)
          end
        end
      end

      defresource CommentTitleBeforePostId, "comments_title_before_post_id" do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:post_id, :uuid, allow_nil?: false, public?: true)
        end

        identities do
          identity(:uniq_title, [:title])
        end

        relationships do
          belongs_to(:post, Post) do
            source_attribute(:post_id)
            destination_attribute(:id)
          end
        end
      end

      before_snapshots =
        AshPostgres.MigrationGenerator.get_snapshots(CommentPostIdBeforeTitle, [
          Post,
          CommentPostIdBeforeTitle
        ])

      after_snapshots =
        AshPostgres.MigrationGenerator.get_snapshots(CommentTitleBeforePostId, [
          Post,
          CommentTitleBeforePostId
        ])

      assert [before_snapshot] = before_snapshots
      assert [after_snapshot] = after_snapshots
      assert Enum.map(before_snapshot.attributes, & &1.source) == [:id, :post_id, :title]
      assert Enum.map(after_snapshot.attributes, & &1.source) == [:id, :title, :post_id]

      before_ops =
        AshPostgres.MigrationGenerator.get_operations_from_snapshots([], before_snapshots)

      after_ops =
        AshPostgres.MigrationGenerator.get_operations_from_snapshots([], after_snapshots)

      assert Enum.any?(
               after_ops,
               &match?(
                 %AshPostgres.MigrationGenerator.Phase.Create{
                   table: "comments_title_before_post_id"
                 },
                 &1
               )
             )

      assert Enum.any?(
               before_ops,
               &match?(
                 %AshPostgres.MigrationGenerator.Phase.Create{
                   table: "comments_post_id_before_title"
                 },
                 &1
               )
             )
    end
  end

  describe "creating initial snapshots" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "the migration sets up resources correctly", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      # the snapshot exists and contains valid json
      assert File.read!(Path.wildcard("#{snapshot_path}/test_repo/posts/*.json"))
             |> Jason.decode!(keys: :atoms!)

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
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

  describe "creating initial snapshots with native uuidv7 on PG 18" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      prev_pg_version_env = System.fetch_env("PG_VERSION")
      System.put_env("PG_VERSION", "18")

      on_exit(fn ->
        case prev_pg_version_env do
          # there was a previous env var set, restore it
          {:ok, value} -> System.put_env("PG_VERSION", value)
          # there was nothing set, delete what we set
          :error -> System.delete_env("PG_VERSION")
        end
      end)

      defposts do
        attributes do
          uuid_v7_primary_key(:id)
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

    test "the migration uses the native uuidv7 function", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      # the snapshot exists and contains valid json
      assert File.read!(Path.wildcard("#{snapshot_path}/test_repo/posts/*.json"))
             |> Jason.decode!(keys: :atoms!)

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      # the migration adds the id using the native uuidv7 function
      assert file_contents =~
               ~S[add :id, :uuid, null: false, default: fragment("uuidv7()"), primary_key: true]
    end
  end

  describe "creating initial snapshots for resources with a schema" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "the migration sets up resources correctly", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      # the snapshot exists and contains valid json
      assert File.read!(Path.wildcard("#{snapshot_path}/test_repo/example.posts/*.json"))
             |> Jason.decode!(keys: :atoms!)

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      # the migration creates the schema
      assert file_contents =~ "execute(\"CREATE SCHEMA IF NOT EXISTS example\")"

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

  describe "custom_indexes with `concurrently: true`" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )
    end

    test "it creates multiple migration files", %{migration_path: migration_path} do
      assert [_, custom_index_migration] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file = File.read!(custom_index_migration)

      assert file =~ ~S[@disable_ddl_transaction true]

      assert file =~ ~S<create index(:posts, [:title], concurrently: true)>
    end
  end

  describe "custom_indexes with `concurrently: true` and an explicit name" do
    test "it gives each generated migration a unique name and module", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      :ok

      defposts do
        postgres do
          custom_indexes do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        name: "repro_case"
      )

      assert [first_migration, second_migration] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      first_contents = File.read!(first_migration)
      second_contents = File.read!(second_migration)

      first_name =
        first_migration
        |> Path.basename(".exs")
        |> then(&Regex.replace(~r/^\d+_/, &1, ""))

      second_name =
        second_migration
        |> Path.basename(".exs")
        |> then(&Regex.replace(~r/^\d+_/, &1, ""))

      assert [_, first_module] = Regex.run(~r/^defmodule\s+(.+)\s+do$/m, first_contents)
      assert [_, second_module] = Regex.run(~r/^defmodule\s+(.+)\s+do$/m, second_contents)

      # Split migrations still need unique derived names and modules, even
      # when the generation run uses an explicit `name`.
      assert first_name != second_name
      assert first_module != second_module
    end
  end

  describe "unique identities with `concurrent_indexes: true`" do
    test "dependent foreign keys are generated only after the unique index migration", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      Code.compiler_options(ignore_module_conflict: true)

      defmodule ConcurrentUniqueTarget do
        use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: nil

        postgres do
          table "concurrent_unique_targets"
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:code, :string, allow_nil?: false, public?: true)
        end

        identities do
          identity(:uniq_code, [:code])
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defmodule ConcurrentUniqueDependent do
        use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: nil

        postgres do
          table "concurrent_unique_dependents"
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:target_code, :string, public?: true)
        end

        relationships do
          belongs_to(:target, ConcurrentUniqueTarget) do
            source_attribute(:target_code)
            destination_attribute(:code)
            attribute_writable?(true)
            allow_nil?(true)
            public?(true)
          end
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defmodule ConcurrentUniqueDomain do
        use Ash.Domain

        resources do
          resource(ConcurrentUniqueTarget)
          resource(ConcurrentUniqueDependent)
        end
      end

      Code.compiler_options(ignore_module_conflict: false)

      AshPostgres.MigrationGenerator.generate(ConcurrentUniqueDomain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        concurrent_indexes: true
      )

      assert [table_migration, unique_index_migration, fk_migration] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      table_contents = File.read!(table_migration)
      index_contents = File.read!(unique_index_migration)
      fk_contents = File.read!(fk_migration)

      # Three steps are generated:
      # 1. create tables without the FK to `:code`
      # 2. create the concurrent unique index on `concurrent_unique_targets.code`
      # 3. add the FK from `concurrent_unique_dependents.target_code`

      # Step 1: tables created, but target_code has no FK reference
      assert table_contents =~ ~S|create table(:concurrent_unique_targets|
      assert table_contents =~ ~S|create table(:concurrent_unique_dependents|
      refute table_contents =~ ~S|references(:concurrent_unique_targets|

      # Step 2: concurrent unique index (in a @disable_ddl_transaction migration)
      assert index_contents =~ ~S|@disable_ddl_transaction true|
      assert index_contents =~ ~S|@disable_migration_lock true|

      assert index_contents =~
               ~S|create unique_index(:concurrent_unique_targets, [:code], name: "concurrent_unique_targets_uniq_code_index", concurrently: true)|

      # Step 3: FK reference added
      assert fk_contents =~
               ~S|modify :target_code, references(:concurrent_unique_targets, column: :code, name: "concurrent_unique_dependents_target_code_fkey", type: :text, prefix: "public")|
    end
  end

  describe "custom_indexes with `null_distinct: false`" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )
    end

    test "it adds nulls_distinct option to create index migration", %{
      migration_path: migration_path
    } do
      assert [custom_index_migration] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file = File.read!(custom_index_migration)

      assert file =~ ~S<create index(:posts, [:uniq_one])>
      assert file =~ ~S<create index(:posts, [:uniq_two], nulls_distinct: false)>
      assert file =~ ~S<create index(:posts, [:uniq_custom_one])>
    end
  end

  describe "custom_indexes with follow up migrations" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

      defposts do
        postgres do
          custom_indexes do
            index([:title])
          end
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
    end

    test "it changes attribute and index in the correct order", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defposts do
        postgres do
          custom_indexes do
            index([:title_short])
          end
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title_short, :string, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file2)

      [up_side, down_side] = String.split(contents, "def down", parts: 2)

      up_side_parts = String.split(up_side, "\n", trim: true)

      assert Enum.find_index(up_side_parts, fn x ->
               x == "rename table(:posts), :title, to: :title_short"
             end) <
               Enum.find_index(up_side_parts, fn x ->
                 x == "create index(:posts, [:title_short])"
               end)

      down_side_parts = String.split(down_side, "\n", trim: true)

      assert Enum.find_index(down_side_parts, fn x ->
               x == "rename table(:posts), :title_short, to: :title"
             end) <
               Enum.find_index(down_side_parts, fn x -> x == "create index(:posts, [:title])" end)
    end
  end

  describe "creating follow up migrations with a composite primary key" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "when removing an element, it recreates the primary key", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, _file2, file3] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file3)

      [up_side, down_side] = String.split(contents, "def down", parts: 2)

      assert up_side =~ ~S[execute("ALTER TABLE \"example.posts\" ADD PRIMARY KEY (id, title)")]
      assert down_side =~ ~S[execute("ALTER TABLE \"example.posts\" ADD PRIMARY KEY (id)")]
    end
  end

  describe "creating a multitenancy resource without composite key, adding it later" do
    setup do
      :ok
    end

    test "create without composite key, then add extra key", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path,
      tenant_migration_path: tenant_migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        tenant_migration_path: tenant_migration_path,
        quiet: false,
        format: false,
        auto_name: true
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        tenant_migration_path: tenant_migration_path,
        quiet: false,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{tenant_migration_path}/**/*_migrate_resources*.exs"))
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
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "when renaming a field, it asks if you are renaming it, and renames it if you are", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~ ~S[rename table(:posts, prefix: "example"), :title, to: :name]
    end

    test "renaming a field honors additional changes", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file2)

      [up_side, down_side] = String.split(contents, "def down", parts: 2)

      up_side_parts =
        String.split(up_side, "\n", trim: true)
        |> Enum.map(&String.trim/1)

      up_rename_index =
        Enum.find_index(up_side_parts, fn x ->
          x == ~S[rename table(:posts, prefix: "example"), :title, to: :name]
        end)

      up_modify_index =
        Enum.find_index(up_side_parts, fn x ->
          x == ~S[modify :name, :text, null: false, default: "fred"]
        end)

      assert up_rename_index < up_modify_index

      down_side_parts =
        String.split(down_side, "\n", trim: true)
        |> Enum.map(&String.trim/1)

      down_modify_index =
        Enum.find_index(down_side_parts, fn x ->
          x == ~S[modify :name, :text, null: true, default: nil]
        end)

      down_rename_index =
        Enum.find_index(down_side_parts, fn x ->
          x == ~S[rename table(:posts, prefix: "example"), :name, to: :title]
        end)

      assert down_modify_index < down_rename_index
    end
  end

  describe "changing global multitenancy" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "when changing multitenancy to global, identities aren't rewritten", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))
    end
  end

  describe "creating follow up migrations" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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

    test "when renaming an attribute of an index, it is properly renamed without modifying the attribute",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file2)
      refute contents =~ "modify"
    end

    test "when renaming an index, it is properly renamed", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[ALTER INDEX posts_title_index RENAME TO titles_r_unique_dawg]
    end

    test "when changing the where clause, it is properly dropped and recreated", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert [file_before, _] =
               String.split(
                 File.read!(file2),
                 ~S{create unique_index(:posts, [:title], name: "posts_title_index", where: "(title != 'fred' and title != 'george')")}
               )

      assert file_before =~
               ~S{drop_if_exists unique_index(:posts, [:title], name: "posts_title_index")}
    end

    test "when adding a field, it adds the field", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :name, :text, null: false]
    end

    test "when renaming a field, it asks if you are renaming it, and renames it if you are", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~ ~S[rename table(:posts), :title, to: :name]
    end

    test "when renaming a field, it asks if you are renaming it, and adds it if you aren't", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, false})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :name, :text, null: false]
    end

    test "when renaming a field, it asks which field you are renaming it to, and renames it if you are",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      # Up migration
      assert File.read!(file2) =~ ~S[rename table(:posts), :title, to: :subject]

      # Down migration
      assert File.read!(file2) =~ ~S[rename table(:posts), :subject, to: :title]
    end

    test "when renaming a field with an identity, it asks which field you are renaming it to, and updates indexes in the correct order",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defposts do
        identities do
          identity(:subject, [:subject])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:subject, :string, public?: true)
        end
      end

      defdomain([Post])

      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :prompt, "subject"})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      contents = File.read!(file2)
      [up_side, down_side] = String.split(contents, "def down", parts: 2)

      up_side_parts =
        String.split(up_side, "\n", trim: true)
        |> Enum.map(&String.trim/1)

      drop_index =
        Enum.find_index(up_side_parts, fn x ->
          x == "drop_if_exists unique_index(:posts, [:title], name: \"posts_title_index\")"
        end)

      rename_table =
        Enum.find_index(up_side_parts, fn x ->
          x == "rename table(:posts), :title, to: :subject"
        end)

      create_index =
        Enum.find_index(up_side_parts, fn x ->
          x == "create unique_index(:posts, [:subject], name: \"posts_subject_index\")"
        end)

      assert drop_index < rename_table
      assert rename_table < create_index

      down_side_parts =
        String.split(down_side, "\n", trim: true)
        |> Enum.map(&String.trim/1)

      drop_index =
        Enum.find_index(down_side_parts, fn x ->
          x ==
            "drop_if_exists unique_index(:posts, [:subject], name: \"posts_subject_index\")"
        end)

      rename_table =
        Enum.find_index(down_side_parts, fn x ->
          x == "rename table(:posts), :subject, to: :title"
        end)

      create_index =
        Enum.find_index(down_side_parts, fn x ->
          x == "create unique_index(:posts, [:title], name: \"posts_title_index\")"
        end)

      assert drop_index < rename_table
      assert rename_table < create_index
    end

    test "when renaming a field, it asks which field you are renaming it to, and adds it if you arent",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :subject, :text, null: false]
    end

    test "when multiple schemas apply to the same table, all attributes are added", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :foobar, :text]

      assert File.read!(file2) =~
               ~S[add :foobar, :text]
    end

    test "when multiple schemas apply to the same table, all identities are added", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
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

    test "when concurrent-indexes flag set to true, identities are added in separate migration",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        concurrent_indexes: true,
        format: false,
        auto_name: true
      )

      assert [_file1, _file2, file3] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file3_content = File.read!(file3)

      assert file3_content =~ ~S[@disable_ddl_transaction true]

      assert file3_content =~
               "create unique_index(:posts, [:title], name: \"posts_unique_title_index\", concurrently: true)"

      assert file3_content =~
               "create unique_index(:posts, [:name], name: \"posts_unique_name_index\", concurrently: true)"
    end

    test "when an attribute exists only on some of the resources that use the same table, it isn't marked as null: false",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file2) =~
               ~S[add :example, :text] <> "\n"

      refute File.read!(file2) =~ ~S[null: false]
    end
  end

  describe "auto incrementing integer, when generated" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "when an integer is generated and default nil, it is a bigserial", %{
      migration_path: migration_path
    } do
      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S[add :id, :bigserial, null: false, primary_key: true]

      assert File.read!(file) =~
               ~S[add :views, :bigint]
    end
  end

  describe "migration_types identity" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defresource(IdentityPost) do
        postgres do
          table "identity_posts"
          repo(AshPostgres.TestRepo)
          migration_types(id: :identity, sequence_id: :identity)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          integer_primary_key(:id)

          attribute(:sequence_id, :integer,
            generated?: true,
            allow_nil?: false,
            public?: true
          )

          attribute(:title, :string, public?: true)
        end
      end

      defmodule IdentityDomain do
        use Ash.Domain

        resources do
          resource(IdentityPost)
        end
      end

      AshPostgres.MigrationGenerator.generate(IdentityDomain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "uses :identity when set in migration_types", %{migration_path: migration_path} do
      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)
      assert file_contents =~ ~S[add :id, :identity, null: false, primary_key: true]
      assert file_contents =~ ~S[add :sequence_id, :identity, null: false]
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

    test "raises an error on pending codegen", %{
      domain: domain,
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      assert_raise Ash.Error.Framework.PendingCodegen, fn ->
        AshPostgres.MigrationGenerator.generate(domain,
          snapshot_path: snapshot_path,
          migration_path: migration_path,
          check: true,
          auto_name: true
        )
      end

      refute File.exists?(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
      refute File.exists?(Path.wildcard("#{snapshot_path}/test_repo/posts/*.json"))
    end
  end

  describe "references" do
    setup do
      :ok
    end

    test "references are inferred automatically", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S[references(:posts, column: :id, name: "posts_post_id_fkey", type: :uuid, prefix: "public")]
    end

    @tag :issue_236
    test "unique index is created before dependent foreign key (issue #236)", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource Template, "templates" do
        attributes do
          uuid_primary_key(:id)
        end
      end

      defresource Phase, "phases" do
        attributes do
          uuid_primary_key(:id)
        end
      end

      defresource TemplatePhase, "template_phase" do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, allow_nil?: false, public?: true)
        end

        identities do
          identity(:id, [:id])
        end

        relationships do
          belongs_to(:template, Template, primary_key?: true, allow_nil?: false, public?: true)
          belongs_to(:phase, Phase, primary_key?: true, allow_nil?: false, public?: true)

          belongs_to(:template_phase, __MODULE__) do
            source_attribute(:follows)
            destination_attribute(:id)
            attribute_writable?(true)
            allow_nil?(true)
            public?(true)
          end
        end
      end

      defdomain([Template, Phase, TemplatePhase])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      unique_index_pos =
        position_of_substring(
          file_contents,
          ~S{create unique_index(:template_phase, [:id], name: "template_phase_id_index")}
        )

      follows_fk_pos = position_of_substring(file_contents, "references(:template_phase")

      assert unique_index_pos && follows_fk_pos,
             "expected migration to contain both the unique index and the follows foreign key"

      assert unique_index_pos < follows_fk_pos,
             "expected unique index creation to appear before the follows foreign key modification"
    end

    test "references are inferred automatically if the attribute has a different type", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S[references(:posts, column: :id, name: "posts_post_id_fkey", type: :text, prefix: "public")]
    end

    test "references allow passing :match_with and :match_type", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{references(:posts, column: :id, with: [related_key_id: :key_id], match: :partial, name: "posts_post_id_fkey", type: :uuid, prefix: "public")}
    end

    test "references generate related index when index? true", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~ ~S{create index(:posts, [:post_id])}
    end

    test "changing only reference index? does not drop and re-add foreign key (issue #611)", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      # First generate: reference with index?: true
      defresource PostRefIdx, "posts" do
        attributes do
          uuid_primary_key(:id)
          attribute(:key_id, :uuid, allow_nil?: false, public?: true)
          attribute(:foobar, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defresource Post2RefIdx, "posts" do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
          attribute(:related_key_id, :uuid, public?: true)
        end

        relationships do
          belongs_to(:post, PostRefIdx, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        postgres do
          references do
            reference(:post, index?: true)
          end
        end
      end

      defmodule DomainRefIdx do
        use Ash.Domain

        resources do
          resource(PostRefIdx)
          resource(Post2RefIdx)
        end
      end

      AshPostgres.MigrationGenerator.generate(DomainRefIdx,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      # Second generate: same reference but index?: false (only index change)
      defresource PostRefNoIdx, "posts" do
        attributes do
          uuid_primary_key(:id)
          attribute(:key_id, :uuid, allow_nil?: false, public?: true)
          attribute(:foobar, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defresource Post2RefNoIdx, "posts" do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
          attribute(:related_key_id, :uuid, public?: true)
        end

        relationships do
          belongs_to(:post, PostRefNoIdx, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        postgres do
          references do
            reference(:post, index?: false)
          end
        end
      end

      defmodule DomainRefNoIdx do
        use Ash.Domain

        resources do
          resource(PostRefNoIdx)
          resource(Post2RefNoIdx)
        end
      end

      AshPostgres.MigrationGenerator.generate(DomainRefNoIdx,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      [_, file2] =
        Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      content = File.read!(file2)

      # Should only drop the index, not touch the foreign key
      assert content =~ ~S{drop_if_exists index(:posts, [:post_id])},
             "migration should drop the reference index when index? changes to false"

      refute content =~ ~S{drop constraint(:posts, "posts_post_id_fkey")},
             "migration should not drop the foreign key when only index? changed (issue #611)"

      refute content =~ ~S{modify :post_id, references(},
             "migration should not modify references when only index? changed (issue #611)"
    end

    test "references with deferrable modifications generate changes with the correct schema", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:key_id, :uuid, allow_nil?: false, public?: true)
          attribute(:foobar, :string, public?: true)
        end

        postgres do
          schema "example"
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
          schema "example"

          references do
            reference(:post, index?: true, deferrable: :initially)
          end
        end
      end

      defdomain([Post, Post2])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

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
          schema "example"

          references do
            reference(:post, index?: true, deferrable: true)
          end
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert file =
               "#{migration_path}/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
               |> Enum.sort()
               |> Enum.at(1)
               |> File.read!()

      assert file =~ ~S{execute("ALTER TABLE example.posts ALTER CONSTRAINT}
    end

    test "index generated by index? true also adds column when using attribute multitenancy", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~ ~S{create index(:posts, [:org_id, :post_id])}
    end

    test "index generated by index? true does not duplicate tenant column when using attribute multitenancy if reference is same as tenant column",
         %{
           snapshot_path: snapshot_path,
           migration_path: migration_path,
           tenant_migration_path: tenant_migration_path
         } do
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

        postgres do
          references do
            reference(:org, index?: true)
          end
        end
      end

      defdomain([Org, Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert file =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))
               |> File.read!()

      assert [up_code, down_code] = String.split(file, "def down do")

      assert up_code =~ ~S{create index(:posts, [:org_id])}
      assert down_code =~ ~S{drop_if_exists index(:posts, [:org_id])}
    end

    test "references merge :match_with and multitenancy attribute", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{references(:users, column: :secondary_id, with: [related_key_id: :key_id, org_id: :org_id], match: :full, name: "user_things_user_id_fkey", type: :uuid, prefix: "public")}
    end

    test "identities using `all_tenants?: true` will not have the condition on multitenancy attribtue added",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{create unique_index(:users, [:name], name: "users_unique_name_index")}
    end

    test "when base_filter changes, `all_tenants?: true` identity is dropped and recreated",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:archived, :boolean, public?: true, default: false)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        identities do
          identity(:unique_name, [:name], all_tenants?: true)
        end

        resource do
          base_filter(expr(archived == false))
        end

        postgres do
          base_filter_sql "archived = false"
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:archived, :boolean, public?: true, default: false)
          attribute(:hidden, :boolean, public?: true, default: false)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        identities do
          identity(:unique_name, [:name], all_tenants?: true)
        end

        resource do
          base_filter(expr(archived == false and hidden == false))
        end

        postgres do
          base_filter_sql "archived = false AND hidden = false"
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      [_first_file, second_file] =
        Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      second_contents = File.read!(second_file)

      assert [up_code, _down_code] = String.split(second_contents, "def down do")

      assert up_code =~
               ~S{drop_if_exists unique_index(:users, [:name], name: "users_unique_name_index")}

      assert up_code =~
               ~S{create unique_index(:users, [:name], where: "(archived = false AND hidden = false)"}
    end

    test "when base_filter changes, `all_tenants?: true` custom index is dropped and recreated",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:archived, :boolean, public?: true, default: false)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        resource do
          base_filter(expr(archived == false))
        end

        postgres do
          base_filter_sql "archived = false"

          custom_indexes do
            index([:name], all_tenants?: true, unique: true, name: "users_active_name_index")
          end
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:archived, :boolean, public?: true, default: false)
          attribute(:hidden, :boolean, public?: true, default: false)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        resource do
          base_filter(expr(archived == false and hidden == false))
        end

        postgres do
          base_filter_sql "archived = false AND hidden = false"

          custom_indexes do
            index([:name], all_tenants?: true, unique: true, name: "users_active_name_index")
          end
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      [_first_file, second_file] =
        Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      second_contents = File.read!(second_file)

      assert [up_code, _down_code] = String.split(second_contents, "def down do")

      assert up_code =~
               ~S{drop_if_exists index(:users, [:name], name: "users_active_name_index")}

      assert up_code =~
               ~S{create index(:users, [:name], name: "users_active_name_index", unique: true, where: "archived = false AND hidden = false")}
    end

    test "when multitenancy changes, `all_tenants?: true` indexes are not rewritten",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:email, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:account_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        identities do
          identity(:scoped_name, [:name])
          identity(:global_email, [:email], all_tenants?: true)
        end

        postgres do
          custom_indexes do
            index([:email], all_tenants?: true, name: "users_global_email_index")
          end
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:email, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:account_id, :uuid, public?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:account_id)
        end

        identities do
          identity(:scoped_name, [:name])
          identity(:global_email, [:email], all_tenants?: true)
        end

        postgres do
          custom_indexes do
            index([:email], all_tenants?: true, name: "users_global_email_index")
          end
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      [_first_file, second_file] =
        Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      second_contents = File.read!(second_file)

      assert second_contents =~
               ~S{drop_if_exists unique_index(:users, [:org_id, :name], name: "users_scoped_name_index")}

      refute second_contents =~ ~S{users_global_email_index}
      refute second_contents =~ ~S{users_global_email_unique_index}
    end

    test "when base_filter and identity index_name change together, only drop and create are emitted",
         %{snapshot_path: snapshot_path, migration_path: migration_path} do
      defresource Org, "orgs" do
        attributes do
          uuid_primary_key(:id, writable?: true)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:id)
        end
      end

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:archived, :boolean, public?: true, default: false)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        identities do
          identity(:unique_name, [:name], all_tenants?: true)
        end

        resource do
          base_filter(expr(archived == false))
        end

        postgres do
          base_filter_sql "archived = false"
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource User, "users" do
        attributes do
          uuid_primary_key(:id, writable?: true)
          attribute(:name, :string, public?: true)
          attribute(:org_id, :uuid, public?: true)
          attribute(:archived, :boolean, public?: true, default: false)
          attribute(:hidden, :boolean, public?: true, default: false)
        end

        multitenancy do
          strategy(:attribute)
          attribute(:org_id)
        end

        identities do
          identity(:unique_name, [:name], all_tenants?: true)
        end

        resource do
          base_filter(expr(archived == false and hidden == false))
        end

        postgres do
          base_filter_sql "archived = false AND hidden = false"
          identity_index_names(unique_name: "renamed_users_unique_name_index")
        end

        relationships do
          belongs_to(:org, Org) do
            public?(true)
          end
        end
      end

      defdomain([Org, User])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      [_first_file, second_file] =
        Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      second_contents = File.read!(second_file)

      assert [up_code, _down_code] = String.split(second_contents, "def down do")

      assert up_code =~
               ~S{drop_if_exists unique_index(:users, [:name], name: "users_unique_name_index")}

      assert up_code =~
               ~S{create unique_index(:users, [:name], where: "(archived = false AND hidden = false)", name: "renamed_users_unique_name_index")}

      refute up_code =~ "ALTER INDEX"
    end

    test "when modified, the foreign key is dropped before modification", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert file =
               "#{migration_path}/**/*_migrate_resources*.exs"
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

    test "references with added only when needed on multitenant resources", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S{references(:users, column: :secondary_id, with: [org_id: :org_id], match: :full, name: "user_things1_user_id_fkey", type: :uuid, prefix: "public")}

      assert File.read!(file) =~
               ~S[references(:users, column: :id, name: "user_things2_user_id_fkey", type: :uuid, prefix: "public")]
    end

    test "references on_delete: {:nilify, columns} works with multitenant resources", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S<references(:groups, column: :id, with: [tenant_id: :tenant_id], name: "items_group_id_fkey", type: :uuid, prefix: "public", on_delete: {:nilify, [:group_id]}>
    end
  end

  describe "check constraints" do
    setup do
      :ok
    end

    test "when added, the constraint is created", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer, public?: true)
          attribute(:title, :string, public?: true)
        end

        postgres do
          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: ~S["price" > 0])

            check_constraint(:title, "title_must_conform_to_format",
              check: ~S[title ~= '("\"\\"\\\"\\\\"\\\\\")']
            )
          end
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

      assert file =
               "#{migration_path}/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
               |> Enum.sort()
               |> Enum.at(0)
               |> File.read!()

      assert file =~
               ~S'''
               create constraint(:posts, :price_must_be_positive, check: """
                 "price" > 0
               """)
               '''

      assert file =~
               ~S'''
               create constraint(:posts, :title_must_conform_to_format, check: """
                 title ~= '("\"\\"\\\"\\\\"\\\\\")'
               """)
               '''

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert file =
               "#{migration_path}/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
               |> Enum.sort()
               |> Enum.at(1)
               |> File.read!()

      assert [_, down] = String.split(file, "def down do")

      assert [_, remaining] =
               String.split(down, "drop_if_exists constraint(:posts, :price_must_be_positive)")

      assert remaining =~
               ~S'''
               create constraint(:posts, :price_must_be_positive, check: """
                 "price" > 0
               """)
               '''
    end

    test "base filters are taken into account, negated", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer, public?: true)
        end

        resource do
          base_filter(expr(price > 10))
        end

        postgres do
          base_filter_sql "price > -10"

          check_constraints do
            check_constraint(:price, "price_must_be_positive", check: "price > 0")
          end
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

      assert file =
               "#{migration_path}/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
               |> Enum.sort()
               |> Enum.at(0)
               |> File.read!()

      assert file =~
               ~S'''
               create constraint(:posts, :price_must_be_positive, check: """
                 (price > 0) OR NOT (price > -10)
               """)
               '''
    end

    test "when removed, the constraint is dropped before modification", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:price, :integer, public?: true)
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert file =
               "#{migration_path}/**/*_migrate_resources*.exs"
               |> Path.wildcard()
               |> Enum.reject(&String.contains?(&1, "extensions"))
               |> Enum.sort()
               |> Enum.at(1)

      assert File.read!(file) =~
               ~S[drop_if_exists constraint(:posts, :price_must_be_positive)]
    end
  end

  describe "polymorphic resources" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      [domain: Domain]
    end

    test "it uses the relationship's table context if it is set", %{
      migration_path: migration_path
    } do
      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert File.read!(file) =~
               ~S[references(:post_comments, column: :id, name: "posts_best_comment_id_fkey", type: :uuid, prefix: "public")]
    end
  end

  describe "default values" do
    setup do
      :ok
    end

    test "when default value is specified that implements EctoMigrationDefault", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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

          attribute(:decimal_list, {:array, :decimal},
            default: [Decimal.new("123.4567890987654321987")],
            public?: true
          )

          attribute(:name, :string, default: "Fred", public?: true)
          attribute(:tag, :atom, default: :value, public?: true)
          attribute(:enabled, :boolean, default: false, public?: true)
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

      assert [file1] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
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

    test "when default value is specified that does not implement EctoMigrationDefault", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
            snapshot_path: snapshot_path,
            migration_path: migration_path,
            quiet: true,
            format: false,
            auto_name: true
          )
        end)

      assert log =~ "`{\"xyz\"}`"

      assert [file1] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file = File.read!(file1)

      assert file =~
               ~S[add :product_code, :binary]
    end
  end

  describe "follow up with references" do
    setup %{snapshot_path: snapshot_path, migration_path: migration_path} do
      :ok

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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      :ok
    end

    test "when changing the primary key, it changes properly", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
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
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
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

  describe "multitenancy identity with tenant attribute" do
    setup do
      :ok
    end

    test "identity including tenant attribute does not duplicate columns in index", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource Channel, "channels" do
        postgres do
          table "channels"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        multitenancy do
          strategy(:attribute)
          attribute(:project_id)
        end

        identities do
          identity(:unique_type_per_project, [:project_id, :type])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:project_id, :uuid, allow_nil?: false, public?: true)
          attribute(:type, :string, allow_nil?: false, public?: true)
          attribute(:name, :string, public?: true)
        end
      end

      defdomain([Channel])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_content = File.read!(file)

      # The index should only have project_id and type, not project_id twice
      assert file_content =~
               ~S{create unique_index(:channels, [:project_id, :type], name: "channels_unique_type_per_project_index")}

      # Make sure it doesn't have duplicate columns
      refute file_content =~
               ~S{create unique_index(:channels, [:project_id, :project_id, :type]}
    end
  end

  describe "decimal precision and scale" do
    setup do
      :ok
    end

    test "creates decimal columns with precision and scale", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource Product do
        postgres do
          table "products"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)

          attribute(:price, :decimal,
            constraints: [precision: 10, scale: 2],
            public?: true,
            allow_nil?: false
          )

          attribute(:weight, :decimal,
            constraints: [precision: 8],
            public?: true,
            allow_nil?: false
          )

          attribute(:rating, :decimal, public?: true, allow_nil?: false)
        end
      end

      defdomain([Product])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_content = File.read!(file)

      # Check that precision and scale are included for the price field
      assert file_content =~ ~S[add :price, :decimal, null: false, precision: 10, scale: 2]

      # Check that only precision is included for the weight field
      assert file_content =~ ~S[add :weight, :decimal, null: false, precision: 8]

      # Check that no precision or scale is included for the rating field
      assert file_content =~ ~S[add :rating, :decimal, null: false]
    end

    test "alters decimal columns with precision and scale changes", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource Product do
        postgres do
          table "products"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:price, :decimal, constraints: [precision: 8, scale: 2], public?: true)
        end
      end

      defdomain([Product])

      # Generate initial migration
      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      # Now update the precision and scale
      defresource Product do
        postgres do
          table "products"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:price, :decimal, constraints: [precision: 12, scale: 4], public?: true)
        end
      end

      # Generate follow-up migration
      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      migration_files =
        Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
        |> Enum.reject(&String.contains?(&1, "extensions"))

      assert length(migration_files) == 2

      # Check the second migration file
      second_migration = File.read!(Enum.at(migration_files, 1))

      # Should contain the alter statement with new precision and scale
      assert second_migration =~ ~S[modify :price, :decimal, precision: 12, scale: 4]
    end

    test "handles arbitrary precision and scale constraints", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource Product do
        postgres do
          table "products"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)

          attribute(:price, :decimal,
            constraints: [precision: :arbitrary, scale: :arbitrary],
            public?: true,
            allow_nil?: false
          )
        end
      end

      defdomain([Product])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_content = File.read!(file)

      # Check that no precision or scale is included when they are :arbitrary
      assert file_content =~ ~S[add :price, :decimal, null: false]
      refute file_content =~ ~S[precision:]
      refute file_content =~ ~S[scale:]
    end

    test "removes precision and scale when changing to arbitrary", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource Product do
        postgres do
          table "products"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)

          attribute(:price, :decimal,
            constraints: [precision: 10, scale: 2],
            public?: true,
            allow_nil?: false
          )
        end
      end

      defdomain([Product])

      # Generate initial migration
      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      # Now change to arbitrary precision and scale
      defresource Product do
        postgres do
          table "products"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)

          attribute(:price, :decimal,
            constraints: [precision: :arbitrary, scale: :arbitrary],
            public?: true,
            allow_nil?: false
          )
        end
      end

      # Generate follow-up migration
      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      migration_files =
        Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
        |> Enum.reject(&String.contains?(&1, "extensions"))

      assert length(migration_files) == 2

      # Check the second migration file
      second_migration = File.read!(Enum.at(migration_files, 1))

      [up, _down] = String.split(second_migration, "def down")

      # Should contain the alter statement removing precision and scale
      assert up =~ ~S[modify :price, :decimal]
      refute up =~ ~S[precision:]
      refute up =~ ~S[scale:]
    end

    test "works with decimal references that have precision and scale", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource Category do
        postgres do
          table "categories"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          attribute(:id, :decimal,
            constraints: [precision: 10, scale: 0],
            primary_key?: true,
            allow_nil?: false,
            public?: true
          )

          attribute(:name, :string, public?: true)
        end
      end

      defresource Product do
        postgres do
          table "products"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)

          attribute(:category_id, :decimal,
            constraints: [precision: 10, scale: 0],
            allow_nil?: false,
            public?: true
          )
        end

        relationships do
          belongs_to(:category, Category) do
            source_attribute(:category_id)
            destination_attribute(:id)
            public?(true)
          end
        end
      end

      defdomain([Category, Product])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_content = File.read!(file)

      # Check that both tables are created with proper decimal precision
      assert file_content =~
               ~S[add :id, :decimal, null: false, precision: 10, scale: 0, primary_key: true]

      assert file_content =~ ~S[add :category_id, :decimal, null: false, precision: 10, scale: 0]
    end
  end

  describe "varchar migration_types on modify" do
    setup do
      :ok
    end

    test "modify includes varchar size when adding migration_types to existing string column", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource MyResource do
        postgres do
          table "my_resources"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blibs, :string, public?: true)
        end
      end

      defdomain([MyResource])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource MyResource do
        postgres do
          table "my_resources"
          migration_types(blibs: {:varchar, 255})
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blibs, :string, public?: true)
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      second_migration = File.read!(file2)

      assert second_migration =~ ~S[modify :blibs, :varchar, size: 255]
      assert second_migration =~ ~S[modify :blibs, :text]
    end

    test "modify includes new size when changing from one varchar size to another", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource MyResource do
        postgres do
          table "my_resources_varchar_change"
          migration_types(blibs: {:varchar, 100})
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blibs, :string, public?: true)
        end
      end

      defdomain([MyResource])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource MyResource do
        postgres do
          table "my_resources_varchar_change"
          migration_types(blibs: {:varchar, 255})
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blibs, :string, public?: true)
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      second_migration = File.read!(file2)

      assert second_migration =~ ~S[modify :blibs, :varchar, size: 255]
      assert second_migration =~ ~S[modify :blibs, :varchar, size: 100]
    end

    test "modify includes size when changing text to binary with migration_types", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource MyResource do
        postgres do
          table "my_resources_binary"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blobs, :string, public?: true)
        end
      end

      defdomain([MyResource])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource MyResource do
        postgres do
          table "my_resources_binary"
          migration_types(blobs: {:binary, 500})
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blobs, :string, public?: true)
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      second_migration = File.read!(file2)

      assert second_migration =~ ~S[modify :blobs, :binary, size: 500]
      assert second_migration =~ ~S[modify :blobs, :text]
    end

    test "modify only affects attribute with migration_types when multiple string attributes exist",
         %{
           snapshot_path: snapshot_path,
           migration_path: migration_path
         } do
      defresource MyResource do
        postgres do
          table "my_resources_multi"
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blibs, :string, public?: true)
          attribute(:blobs, :string, public?: true)
        end
      end

      defdomain([MyResource])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      defresource MyResource do
        postgres do
          table "my_resources_multi"
          migration_types(blibs: {:varchar, 255})
          repo(AshPostgres.TestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:blibs, :string, public?: true)
          attribute(:blobs, :string, public?: true)
        end
      end

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [_file1, file2] =
               Enum.sort(Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs"))
               |> Enum.reject(&String.contains?(&1, "extensions"))

      second_migration = File.read!(file2)

      assert second_migration =~ ~S[modify :blibs, :varchar, size: 255]
      refute second_migration =~ ~S[modify :blobs]
    end
  end

  describe "create_table_options" do
    setup do
      :ok
    end

    test "includes create_table_options in regular table migration", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path,
      tenant_migration_path: tenant_migration_path
    } do
      defposts do
        postgres do
          table "posts"
          create_table_options("PARTITION BY RANGE (id)")
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          create_timestamp(:inserted_at)
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

      assert [file] =
               Path.wildcard("#{migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      assert file_contents =~
               ~S[create table(:posts, primary_key: false, options: "PARTITION BY RANGE (id)") do]
    end

    test "includes create_table_options in context-based multitenancy migration", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path,
      tenant_migration_path: tenant_migration_path
    } do
      defposts do
        postgres do
          table "posts"
          create_table_options("PARTITION BY RANGE (id)")
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
          attribute(:user_id, :integer, public?: true)
        end

        multitenancy do
          strategy(:context)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        tenant_migration_path: tenant_migration_path,
        quiet: true,
        format: false,
        auto_name: true
      )

      assert [file] =
               Path.wildcard("#{tenant_migration_path}/**/*_migrate_resources*.exs")
               |> Enum.reject(&String.contains?(&1, "extensions"))

      file_contents = File.read!(file)

      assert file_contents =~
               ~S[create table(:posts, primary_key: false, prefix: prefix(), options: "PARTITION BY RANGE (id)") do]
    end
  end

  describe "dropping tables when resources are removed" do
    test "generates drop table migration when a resource is removed from the domain", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource PostForDrop, "posts_for_drop" do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defresource MessageForDrop, "messages_for_drop" do
        attributes do
          uuid_primary_key(:id)
          attribute(:body, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([PostForDrop, MessageForDrop])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "add_posts_and_messages"
      )

      migration_files =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      assert migration_files != []

      first_migration = File.read!(List.first(migration_files))
      assert first_migration =~ "create table(:posts_for_drop"
      assert first_migration =~ "create table(:messages_for_drop"

      assert File.exists?(Path.join(snapshot_path, "test_repo/posts_for_drop"))
      assert File.exists?(Path.join(snapshot_path, "test_repo/messages_for_drop"))

      defdomain([PostForDrop])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "remove_messages"
      )

      migration_files_after =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      assert length(migration_files_after) >= 2

      latest_migration =
        migration_files_after
        |> List.last()
        |> File.read!()

      assert latest_migration =~ "drop table(:messages_for_drop)",
             "Expected migration to contain 'drop table(:messages_for_drop)', got:\n#{latest_migration}"

      refute File.exists?(Path.join(snapshot_path, "test_repo/messages_for_drop")),
             "Orphan snapshot dir should be removed after generating drop migration"

      assert File.exists?(Path.join(snapshot_path, "test_repo/posts_for_drop"))
    end

    test "second generate after drop reports no changes", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource SoloPost, "solo_posts" do
        attributes do
          uuid_primary_key(:id)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([SoloPost])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "add_solo"
      )

      count_before =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> length()

      defresource OtherResource, "other_table" do
        attributes do
          uuid_primary_key(:id)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([OtherResource])

      send(self(), {:mix_shell_input, :yes?, false})
      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "drop_solo_add_other"
      )

      count_after_first_drop =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> length()

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "no_op"
      )

      count_after_second =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> length()

      assert count_after_second == count_after_first_drop,
             "Expected no new migration files (count #{count_after_first_drop}), got #{count_after_second}"
    end

    test "when user opts out of drop, snapshot is updated and we do not ask again", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource OptOutPost, "opt_out_posts" do
        attributes do
          uuid_primary_key(:id)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defresource OptOutMessage, "opt_out_messages" do
        attributes do
          uuid_primary_key(:id)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([OptOutPost, OptOutMessage])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "add_opt_out_tables"
      )

      assert File.exists?(Path.join(snapshot_path, "test_repo/opt_out_messages"))

      defdomain([OptOutPost])

      send(self(), {:mix_shell_input, :yes?, false})

      count_before =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> length()

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "would_remove_opt_out_messages"
      )

      count_after_opt_out =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> length()

      assert count_after_opt_out == count_before,
             "Expected no new migration when opting out of drop, got #{count_after_opt_out - count_before} new file(s)"

      assert File.exists?(Path.join(snapshot_path, "test_repo/opt_out_messages")),
             "Opted-out table snapshot dir should remain"

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "no_op_after_opt_out"
      )

      count_after_second =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> length()

      assert count_after_second == count_after_opt_out,
             "Expected no new migration on second run after opt-out (count #{count_after_opt_out}), got #{count_after_second}"

      assert File.exists?(Path.join(snapshot_path, "test_repo/opt_out_messages"))
    end

    test "drop table migration uses correct prefix when resource has schema", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource SchemaPost, "schema_posts" do
        postgres do
          table "schema_posts"
          schema "my_schema"
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([SchemaPost])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "add_schema_post"
      )

      defresource DummyForSchema, "dummy_table" do
        attributes do
          uuid_primary_key(:id)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([DummyForSchema])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "remove_schema_post"
      )

      migration_files =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      latest = File.read!(List.last(migration_files))

      assert latest =~ "drop table(:schema_posts"
      assert latest =~ ~S(prefix: "my_schema")
    end

    test "drop table migration orders dependent tables before referenced tables", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource CompanyForDropOrder, "companies_for_drop_order" do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end
      end

      defresource ProjectForDropOrder, "projects_for_drop_order" do
        attributes do
          uuid_primary_key(:id)
          attribute(:name, :string, public?: true)
        end

        relationships do
          belongs_to(:company, CompanyForDropOrder) do
            allow_nil?(false)
            public?(true)
          end
        end

        postgres do
          references do
            reference(:company, on_delete: :delete)
          end
        end
      end

      defresource TaskForDropOrder, "tasks_for_drop_order" do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end

        relationships do
          belongs_to(:project, ProjectForDropOrder) do
            allow_nil?(false)
            public?(true)
          end
        end

        postgres do
          references do
            reference(:project, on_delete: :delete)
          end
        end
      end

      defresource KeepaliveForDropOrder, "keepalive_for_drop_order" do
        attributes do
          uuid_primary_key(:id)
        end
      end

      defdomain([
        CompanyForDropOrder,
        ProjectForDropOrder,
        TaskForDropOrder,
        KeepaliveForDropOrder
      ])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "add_drop_order_resources"
      )

      defdomain([KeepaliveForDropOrder])

      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :yes?, true})
      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "remove_drop_order_resources"
      )

      latest_migration =
        migration_path
        |> Path.join("**/*remove_drop_order_resources*.exs")
        |> Path.wildcard()
        |> List.first()
        |> File.read!()

      task_pos = position_of_substring(latest_migration, "drop table(:tasks_for_drop_order)")

      project_pos =
        position_of_substring(latest_migration, "drop table(:projects_for_drop_order)")

      company_pos =
        position_of_substring(latest_migration, "drop table(:companies_for_drop_order)")

      assert is_integer(task_pos)
      assert is_integer(project_pos)
      assert is_integer(company_pos)
      assert task_pos < project_pos
      assert project_pos < company_pos
    end
  end

  describe "renaming tables when resources change" do
    test "generates a rename table migration when a resource table is renamed", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource MessageRename, "messages_rename" do
        attributes do
          uuid_primary_key(:id)
          attribute(:body, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([MessageRename])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "add_messages_rename"
      )

      migration_files_before =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      assert migration_files_before != []

      defresource MessageRename, "messages_rename_new" do
        postgres do
          table "messages_rename_new"
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:body, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([MessageRename])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "rename_messages_table"
      )

      migration_files_after =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      assert length(migration_files_after) >= length(migration_files_before) + 1

      latest_migration =
        migration_files_after
        |> List.last()
        |> File.read!()

      assert latest_migration =~
               "rename table(:messages_rename), to: table(:messages_rename_new)"

      refute latest_migration =~ "drop table(:messages_rename)"
      refute latest_migration =~ "create table(:messages_rename_new"
    end

    test "rename table migration respects schema prefix", %{
      snapshot_path: snapshot_path,
      migration_path: migration_path
    } do
      defresource SchemaMessageRename, "schema_messages_rename" do
        postgres do
          table "schema_messages_rename"
          schema "my_schema_rename"
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:body, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([SchemaMessageRename])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "add_schema_messages_rename"
      )

      defresource SchemaMessageRename, "schema_messages_rename_new" do
        postgres do
          table "schema_messages_rename_new"
          schema "my_schema_rename"
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:body, :string, public?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end
      end

      defdomain([SchemaMessageRename])

      send(self(), {:mix_shell_input, :yes?, true})

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: migration_path,
        quiet: true,
        format: false,
        auto_name: true,
        name: "rename_schema_messages_table"
      )

      migration_files =
        Path.wildcard("#{migration_path}/**/*.exs")
        |> Enum.reject(&String.contains?(&1, "extensions"))
        |> Enum.sort()

      latest =
        migration_files
        |> List.last()
        |> File.read!()

      assert latest =~
               ~S[rename table(:schema_messages_rename, prefix: "my_schema_rename"), to: table(:schema_messages_rename_new, prefix: "my_schema_rename")]
    end
  end
end
