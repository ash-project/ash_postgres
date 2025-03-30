defmodule AshPostgres.DevMigrationsTest do
  use AshPostgres.RepoCase, async: false
  @moduletag :migration

  import ExUnit.CaptureLog

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

  defmacrop defposts(mod \\ Post, do: body) do
    quote do
      defresource unquote(mod) do
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

  describe "--dev option" do
    setup do
      on_exit(fn ->
        resource_dev_path = "priv/resource_snapshots/dev_test_repo"
        resource_files = File.ls!(resource_dev_path)
        Enum.each(resource_files, &File.rm_rf!(Path.join(resource_dev_path, &1)))
        migrations_dev_path = "priv/dev_test_repo/migrations"
        migration_files = File.ls!(migrations_dev_path)
        Enum.each(migration_files, &File.rm!(Path.join(migrations_dev_path, &1)))
        tenant_migrations_dev_path = "priv/dev_test_repo/tenant_migrations"
        tenant_migration_files = File.ls!(tenant_migrations_dev_path)
        Enum.each(tenant_migration_files, &File.rm!(Path.join(tenant_migrations_dev_path, &1)))
        AshPostgres.DevTestRepo.query!("DROP TABLE posts")
      end)
    end

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
        dev: true
      )

      assert [_migration] =
               Enum.sort(
                 Path.wildcard("priv/dev_test_repo/migrations/**/*_migrate_resources*.exs")
               )
               |> Enum.reject(&String.contains?(&1, "extensions"))

      capture_log(fn -> migrate() end) =~ "create table posts"
      capture_log(fn -> migrate() end) =~ "create table posts"

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "priv/resource_snapshots",
        migration_path: "priv/dev_test_repo/migrations"
      )

      capture_log(fn -> migrate() end) =~ "create table posts"
    end
  end

  describe "--dev option tenant" do
    setup do
      on_exit(fn ->
        resource_dev_path = "priv/resource_snapshots/dev_test_repo"
        resource_files = File.ls!(resource_dev_path)
        Enum.each(resource_files, &File.rm_rf!(Path.join(resource_dev_path, &1)))
        migrations_dev_path = "priv/dev_test_repo/migrations"
        migration_files = File.ls!(migrations_dev_path)
        Enum.each(migration_files, &File.rm!(Path.join(migrations_dev_path, &1)))
        tenant_migrations_dev_path = "priv/dev_test_repo/tenant_migrations"
        tenant_migration_files = File.ls!(tenant_migrations_dev_path)
        Enum.each(tenant_migration_files, &File.rm!(Path.join(tenant_migrations_dev_path, &1)))
      end)
    end

    test "rolls back dev migrations before deleting" do
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
      capture_log(fn -> tenant_migrate() end) |> dbg()

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "priv/resource_snapshots",
        migration_path: "priv/dev_test_repo/migrations",
        tenant_migration_path: "priv/dev_test_repo/tenant_migrations",
        dev: true
      )

      assert [] =
               Enum.sort(
                 Path.wildcard("priv/dev_test_repo/migrations/**/*_migrate_resources*.exs")
               )
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert [_tenant_migration] =
               Enum.sort(
                 Path.wildcard("priv/dev_test_repo/tenant_migrations/**/*_migrate_resources*.exs")
               )
               |> Enum.reject(&String.contains?(&1, "extensions"))

      assert capture_log(fn -> tenant_migrate() end) =~ "create table posts"
      assert capture_log(fn -> tenant_migrate() end) =~ "create table posts"

      AshPostgres.MigrationGenerator.generate(Domain,
        snapshot_path: "priv/resource_snapshots",
        migration_path: "priv/dev_test_repo/migrations",
        tenant_migration_path: "priv/dev_test_repo/tenant_migrations"
      )

      assert capture_log(fn -> tenant_migrate() end) =~ "create table posts"
    end
  end

  defp migrate do
    Mix.Tasks.AshPostgres.Migrate.run([
      "--migrations-path",
      "priv/dev_test_repo/migrations",
      "--repo",
      "AshPostgres.DevTestRepo"
    ])
  end

  defp tenant_migrate do
    Mix.Tasks.AshPostgres.Migrate.run([
      "--migrations-path",
      "priv/dev_test_repo/tenant_migrations",
      "--repo",
      "AshPostgres.DevTestRepo",
      "--tenants"
    ])
  end
end
