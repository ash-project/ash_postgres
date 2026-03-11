# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ConcurrentIndexMultitenancyTest do
  use AshPostgres.RepoCase, async: false

  import ExUnit.CaptureLog

  alias AshPostgres.MultiTenancy

  @temp_migrations_dir "priv/test_repo/temp_tenant_migrations"

  setup do
    # Create temporary migrations directory
    File.mkdir_p!(@temp_migrations_dir)

    # Ensure create_tenant!/2 and migrate_tenant/3 read tenant migrations from our temp directory.
    original_repo_env = Application.get_env(:ash_postgres, AshPostgres.TestRepo, [])

    Application.put_env(
      :ash_postgres,
      AshPostgres.TestRepo,
      Keyword.put(original_repo_env, :tenant_migrations_path, @temp_migrations_dir)
    )

    on_exit(fn ->
      File.rm_rf!(@temp_migrations_dir)
      Application.put_env(:ash_postgres, AshPostgres.TestRepo, original_repo_env)

      test_tenants = [
        "test_tenant_regular",
        "test_tenant_warning"
      ]

      for tenant <- test_tenants do
        try do
          Ecto.Adapters.SQL.query!(
            AshPostgres.TestRepo,
            "DROP SCHEMA IF EXISTS \"#{tenant}\" CASCADE",
            []
          )
        rescue
          _ -> :ok
        end
      end
    end)

    :ok
  end

  describe "tenant migrations with multitenancy" do
    test "migrate_tenant works with regular (non-concurrent) migration" do
      tenant_name = "test_tenant_regular"
      migration_file = Path.join(@temp_migrations_dir, "20250101000001_create_table_regular.exs")

      migration_content = """
      defmodule AshPostgres.TestRepo.TempTenantMigrations.CreateTableRegular do
        use Ecto.Migration

        def up do
          create table(:regular_table, primary_key: false, prefix: prefix()) do
            add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true
            add :name, :text
            add :status, :text
          end

          create index(:regular_table, [:status], prefix: prefix())
        end

        def down do
          drop index(:regular_table, [:status], prefix: prefix())
          drop table(:regular_table, prefix: prefix())
        end
      end
      """

      File.write!(migration_file, migration_content)

      Ecto.Adapters.SQL.query!(
        AshPostgres.TestRepo,
        "CREATE SCHEMA IF NOT EXISTS \"#{tenant_name}\"",
        []
      )

      assert :ok = try_migrate_tenant(tenant_name, @temp_migrations_dir)

      assert schema_exists?(tenant_name)
      assert table_exists?(tenant_name, "regular_table")
      assert index_exists?(tenant_name, "regular_table", "regular_table_status_index")
    end

    test "logs warning when @disable_ddl_transaction migration runs inside a transaction" do
      tenant_name = "test_tenant_warning"

      migration_file =
        Path.join(@temp_migrations_dir, "20250101000001_create_table_with_attr.exs")

      # Migration has @disable_ddl_transaction but only creates a table (no CONCURRENTLY).
      # This lets the migration succeed while still triggering the warning when run in a transaction.
      migration_content = """
      defmodule AshPostgres.TestRepo.TempTenantMigrations.CreateTableWithAttr do
        use Ecto.Migration

        @disable_ddl_transaction true

        def up do
          create table(:warning_test_table, primary_key: false, prefix: prefix()) do
            add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true
            add :name, :text
          end
        end

        def down do
          drop table(:warning_test_table, prefix: prefix())
        end
      end
      """

      File.write!(migration_file, migration_content)

      Ecto.Adapters.SQL.query!(
        AshPostgres.TestRepo,
        "CREATE SCHEMA IF NOT EXISTS \"#{tenant_name}\"",
        []
      )

      Ecto.Migration.SchemaMigration.ensure_schema_migrations_table!(
        AshPostgres.TestRepo,
        AshPostgres.TestRepo.config(),
        prefix: tenant_name
      )

      log =
        capture_log(fn ->
          AshPostgres.TestRepo.transaction(fn ->
            MultiTenancy.migrate_tenant(tenant_name, AshPostgres.TestRepo, @temp_migrations_dir)
          end)
        end)

      assert log =~ "@disable_ddl_transaction"
      assert log =~ "transaction"
      assert log =~ "transaction?: false"
    end
  end

  defp try_migrate_tenant(tenant_name, migrations_path) do
    MultiTenancy.migrate_tenant(tenant_name, AshPostgres.TestRepo, migrations_path)
    :ok
  end

  defp schema_exists?(schema_name) do
    result =
      Ecto.Adapters.SQL.query!(
        AshPostgres.TestRepo,
        """
        SELECT schema_name
        FROM information_schema.schemata
        WHERE schema_name = $1
        """,
        [schema_name]
      )

    case result.rows do
      [[^schema_name]] -> true
      _ -> false
    end
  end

  defp table_exists?(schema_name, table_name) do
    result =
      Ecto.Adapters.SQL.query!(
        AshPostgres.TestRepo,
        """
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = $1 AND table_name = $2
        """,
        [schema_name, table_name]
      )

    case result.rows do
      [[^table_name]] -> true
      _ -> false
    end
  end

  defp index_exists?(schema_name, table_name, index_name) do
    result =
      Ecto.Adapters.SQL.query!(
        AshPostgres.TestRepo,
        """
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = $1 AND tablename = $2 AND indexname = $3
        """,
        [schema_name, table_name, index_name]
      )

    case result.rows do
      [[^index_name]] -> true
      _ -> false
    end
  end
end
