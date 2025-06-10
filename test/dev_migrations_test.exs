defmodule AshPostgres.DevMigrationsTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration

  import ExUnit.CaptureLog
  require Logger

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    current_shell = Mix.shell()

    :ok = Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(current_shell)
    end)

    Sandbox.checkout(AshPostgres.DevTestRepo)
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
    resource_dev_path = "priv/resource_snapshots/dev_test_repo"

    initial_resource_files =
      if File.exists?(resource_dev_path), do: File.ls!(resource_dev_path), else: []

    migrations_dev_path = "priv/dev_test_repo/migrations"

    initial_migration_files =
      if File.exists?(migrations_dev_path), do: File.ls!(migrations_dev_path), else: []

    tenant_migrations_dev_path = "priv/dev_test_repo/tenant_migrations"

    initial_tenant_migration_files =
      if File.exists?(tenant_migrations_dev_path),
        do: File.ls!(tenant_migrations_dev_path),
        else: []

    clean = fn ->
      if File.exists?(resource_dev_path) do
        current_resource_files = File.ls!(resource_dev_path)
        new_resource_files = current_resource_files -- initial_resource_files
        Enum.each(new_resource_files, &File.rm_rf!(Path.join(resource_dev_path, &1)))
      end

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
    test "rolls back dev migrations before deleting" do
      defposts do
        attributes do
          uuid_primary_key(:id)
          attribute(:title, :string, public?: true)
        end
      end

      defdomain([Post])

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "priv/resource_snapshots",
        migration_path: "priv/dev_test_repo/migrations",
        dev: true,
        auto_name: true
      )

      assert [_extensions, migration, _migration] =
               Path.wildcard("priv/dev_test_repo/migrations/**/*_migrate_resources*.exs")

      assert capture_log(fn -> migrate(migration) end) =~ "create table posts"

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "priv/resource_snapshots",
        migration_path: "priv/dev_test_repo/migrations",
        auto_name: true
      )

      assert capture_log(fn -> migrate(migration) end) =~ "create table posts"
    end
  end

  describe "--dev option tenant" do
    test "rolls back dev migrations before deleting" do
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
        snapshot_path: "priv/resource_snapshots",
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
        snapshot_path: "priv/resource_snapshots",
        migration_path: "priv/dev_test_repo/migrations",
        tenant_migration_path: "priv/dev_test_repo/tenant_migrations",
        auto_name: true
      )

      assert [_tenant_migration] =
               Enum.sort(
                 Path.wildcard("priv/dev_test_repo/tenant_migrations/**/*_migrate_resources*.exs")
               )
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert capture_log(fn -> tenant_migrate() end) =~ "create table org_#{org.id}.posts"
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
end
