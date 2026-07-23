# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.DevMigrationsTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration
  @moduletag :tmp_dir

  alias Ecto.Adapters.SQL.Sandbox

  setup %{tmp_dir: tmp_dir} do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)

    Sandbox.checkout(AshPostgres.DevTestRepo)

    # Copy existing snapshots to tmp dir so the generator doesn't
    # re-generate extensions or delete orphan snapshots from priv/
    snapshot_path = Path.join(tmp_dir, "snapshots")
    source = "priv/resource_snapshots"

    if File.exists?(source) do
      File.cp_r!(source, snapshot_path)
    end

    %{snapshot_path: snapshot_path}
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

  defmacrop defposts(do: body) do
    quote do
      defresource Post do
        postgres do
          table "posts"
          repo(AshPostgres.DevTestRepo)

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

  setup do
    migrations_dev_path = "priv/dev_test_repo/migrations"

    initial_migration_files =
      if File.exists?(migrations_dev_path), do: File.ls!(migrations_dev_path), else: []

    tenant_migrations_dev_path = "priv/dev_test_repo/tenant_migrations"

    initial_tenant_migration_files =
      if File.exists?(tenant_migrations_dev_path),
        do: File.ls!(tenant_migrations_dev_path),
        else: []

    clean = fn ->
      if File.exists?(migrations_dev_path) do
        current_migration_files = File.ls!(migrations_dev_path)
        new_migration_files = current_migration_files -- initial_migration_files
        Enum.each(new_migration_files, &File.rm!(Path.join(migrations_dev_path, &1)))
      end

      if File.exists?(tenant_migrations_dev_path) do
        current_tenant_migration_files = File.ls!(tenant_migrations_dev_path)

        new_tenant_migration_files =
          current_tenant_migration_files -- initial_tenant_migration_files

        Enum.each(
          new_tenant_migration_files,
          &File.rm!(Path.join(tenant_migrations_dev_path, &1))
        )
      end

      AshPostgres.DevTestRepo.query!("DROP TABLE IF EXISTS posts")
    end

    clean.()

    on_exit(clean)
  end

  describe "--dev option" do
    test "rolls back dev migrations before deleting", %{snapshot_path: snapshot_path} do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: "priv/dev_test_repo/migrations",
        dev: true,
        auto_name: true
      )

      assert [_extensions, migration, _migration] =
               Path.wildcard("priv/dev_test_repo/migrations/**/*_migrate_resources*.exs")

      migrate(migration)
      assert table_exists?("posts")

      # Generating without dev: true rolls back the dev migration (dropping the table)
      # and creates a permanent migration in its place
      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: "priv/dev_test_repo/migrations",
        auto_name: true
      )

      refute table_exists?("posts")

      migrate(migration)
      assert table_exists?("posts")
    end
  end

  describe "--dev option tenant" do
    test "rolls back dev migrations before deleting", %{snapshot_path: snapshot_path} do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true, primary_key?: true, allow_nil?: false)
        end

        multitenancy do
          strategy(:context)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: "priv/dev_test_repo/migrations",
        tenant_migration_path: "priv/dev_test_repo/tenant_migrations",
        dev: true,
        auto_name: true
      )

      org =
        AshPostgres.MultitenancyTest.DevMigrationsOrg
        |> Ash.Changeset.for_create(:create, %{name: "test1"}, authorize?: false)
        |> Ash.create!()

      assert [_] =
               Enum.sort(
                 Path.wildcard("priv/dev_test_repo/migrations/**/*_migrate_resources*.exs")
               )
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert [_tenant_migration] =
               Enum.sort(
                 Path.wildcard("priv/dev_test_repo/tenant_migrations/**/*_migrate_resources*.exs")
               )
               |> Enum.reject(&String.contains?(&1, "extensions"))

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: "priv/dev_test_repo/migrations",
        tenant_migration_path: "priv/dev_test_repo/tenant_migrations",
        auto_name: true
      )

      assert [_tenant_migration] =
               Enum.sort(
                 Path.wildcard("priv/dev_test_repo/tenant_migrations/**/*_migrate_resources*.exs")
               )
               |> Enum.reject(&String.contains?(&1, "extensions"))

      tenant_migrate()
      assert table_exists?("posts", "org_#{org.id}")
    end
  end

  describe "composite foreign keys" do
    # https://github.com/ash-project/ash_postgres/issues/805
    #
    # The exact resource/table names are load-bearing: the bug was an
    # ordering tie-break in the generator's dependency resolution, and
    # renaming these resources made it disappear.
    test "a match_with reference's generated migration applies cleanly", %{
      snapshot_path: snapshot_path
    } do
      defresource Site do
        postgres do
          table "sites"
          repo(AshPostgres.DevTestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      defresource A do
        postgres do
          table "as"
          repo(AshPostgres.DevTestRepo)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          belongs_to :site, Site do
            allow_nil?(false)
            primary_key?(true)
          end
        end
      end

      defresource Junction do
        postgres do
          table "junctions"
          repo(AshPostgres.DevTestRepo)

          references do
            reference(:a, match_with: [site_id: :site_id])
          end
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        attributes do
          uuid_primary_key(:id)
        end

        relationships do
          belongs_to :a, A do
            allow_nil?(false)
          end

          belongs_to :site, Site do
            allow_nil?(false)
            primary_key?(true)
          end
        end
      end

      defdomain([Site, A, Junction])

      # The copied snapshots include tables (e.g. multitenant_orgs) that are
      # not in this domain; without this the generator prompts about
      # renaming/dropping them as orphans.
      File.rm_rf!(Path.join(snapshot_path, "dev_test_repo/multitenant_orgs"))

      on_exit(fn ->
        AshPostgres.DevTestRepo.query!(
          ~s(DROP TABLE IF EXISTS "junctions", "as", "sites" CASCADE)
        )
      end)

      existing_files = Path.wildcard("priv/dev_test_repo/migrations/**/*.exs")

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: snapshot_path,
        migration_path: "priv/dev_test_repo/migrations",
        auto_name: true
      )

      assert [_new_file] =
               Path.wildcard("priv/dev_test_repo/migrations/**/*.exs") -- existing_files

      migrate(existing_files |> Enum.sort() |> List.last())

      assert table_exists?("sites")
      assert table_exists?("as")
      assert table_exists?("junctions")
    end
  end

  defp migrate(after_file) do
    AshPostgres.MultiTenancy.migrate_tenant(
      nil,
      AshPostgres.DevTestRepo,
      "priv/dev_test_repo/migrations",
      after_file
    )
  end

  defp tenant_migrate do
    for tenant <- AshPostgres.DevTestRepo.all_tenants() do
      AshPostgres.MultiTenancy.migrate_tenant(
        tenant,
        AshPostgres.DevTestRepo,
        "priv/dev_test_repo/tenant_migrations"
      )
    end
  end

  defp table_exists?(table, schema \\ "public") do
    %{rows: [[exists]]} =
      AshPostgres.DevTestRepo.query!(
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = $2)",
        [schema, table]
      )

    exists
  end
end
