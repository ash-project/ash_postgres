# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ConcurrentIndexMultitenancyTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.MultiTenancy

  @temp_migrations_dir "priv/test_repo/temp_tenant_migrations"

  setup do
    # Create temporary migrations directory
    File.mkdir_p!(@temp_migrations_dir)

    # Ensure create_tenant!/2 reads tenant migrations from our temp directory.
    # AshPostgres.MultiTenancy.create_tenant!/2 does not accept an explicit migrations_path,
    # so we temporarily set the repo config value it consults.
    original_repo_env = Application.get_env(:ash_postgres, AshPostgres.TestRepo, [])

    Application.put_env(
      :ash_postgres,
      AshPostgres.TestRepo,
      Keyword.put(original_repo_env, :tenant_migrations_path, @temp_migrations_dir)
    )

    on_exit(fn ->
      # Clean up temporary migrations directory
      File.rm_rf!(@temp_migrations_dir)

      # Restore repo config
      Application.put_env(:ash_postgres, AshPostgres.TestRepo, original_repo_env)

      # Clean up any test schemas
      test_tenants = [
        "test_tenant_concurrent",
        "test_tenant_regular",
        "test_tenant_mixed",
        "test_tenant_multiple_concurrent"
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

  describe "concurrent index migrations with multitenancy" do
    test "create_tenant! works with concurrent index migration" do
      tenant_name = "test_tenant_concurrent"
      migration_file = Path.join(@temp_migrations_dir, "20250101000001_create_table_with_concurrent_index.exs")

      # Create migration file with concurrent index
      migration_content = """
      defmodule AshPostgres.TestRepo.TempTenantMigrations.CreateTableWithConcurrentIndex do
        use Ecto.Migration

        @disable_ddl_transaction true

        def up do
          create table(:test_table, primary_key: false, prefix: prefix()) do
            add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true
            add :name, :text
            add :email, :text
          end

          create index(:test_table, [:email], concurrently: true, prefix: prefix())
        end

        def down do
          drop index(:test_table, [:email], prefix: prefix())
          drop table(:test_table, prefix: prefix())
        end
      end
      """

      File.write!(migration_file, migration_content)

      # Create tenant - this should succeed without transaction errors
      assert :ok = try_create_tenant(tenant_name, @temp_migrations_dir)

      # Verify schema exists
      assert schema_exists?(tenant_name)

      # Verify table exists
      assert table_exists?(tenant_name, "test_table")

      # Verify concurrent index exists
      assert index_exists?(tenant_name, "test_table", "test_table_email_index")
    end

    test "migrate_tenant works with regular (non-concurrent) migration" do
      tenant_name = "test_tenant_regular"
      migration_file = Path.join(@temp_migrations_dir, "20250101000001_create_table_regular.exs")

      # Create migration file without concurrent index
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

      # Create schema first
      Ecto.Adapters.SQL.query!(
        AshPostgres.TestRepo,
        "CREATE SCHEMA IF NOT EXISTS \"#{tenant_name}\"",
        []
      )

      # Migrate tenant - this should succeed
      assert :ok = try_migrate_tenant(tenant_name, @temp_migrations_dir)

      # Verify schema exists
      assert schema_exists?(tenant_name)

      # Verify table exists
      assert table_exists?(tenant_name, "regular_table")

      # Verify index exists
      assert index_exists?(tenant_name, "regular_table", "regular_table_status_index")
    end

    test "migrate_tenant works with mixed migrations (concurrent and non-concurrent)" do
      tenant_name = "test_tenant_mixed"

      # Create first migration without concurrent index
      migration1_file = Path.join(@temp_migrations_dir, "20250101000001_create_table_first.exs")
      migration1_content = """
      defmodule AshPostgres.TestRepo.TempTenantMigrations.CreateTableFirst do
        use Ecto.Migration

        def up do
          create table(:first_table, primary_key: false, prefix: prefix()) do
            add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true
            add :name, :text
          end

          create index(:first_table, [:name], prefix: prefix())
        end

        def down do
          drop index(:first_table, [:name], prefix: prefix())
          drop table(:first_table, prefix: prefix())
        end
      end
      """

      File.write!(migration1_file, migration1_content)

      # Create second migration with concurrent index
      migration2_file = Path.join(@temp_migrations_dir, "20250101000002_add_concurrent_index.exs")
      migration2_content = """
      defmodule AshPostgres.TestRepo.TempTenantMigrations.AddConcurrentIndex do
        use Ecto.Migration

        @disable_ddl_transaction true

        def up do
          create index(:first_table, [:name], concurrently: true, name: :name_concurrent_index, prefix: prefix())
        end

        def down do
          drop index(:first_table, [:name], name: :name_concurrent_index, prefix: prefix())
        end
      end
      """

      File.write!(migration2_file, migration2_content)

      # Create tenant - this should succeed with both migrations
      assert :ok = try_create_tenant(tenant_name, @temp_migrations_dir)

      # Verify schema exists
      assert schema_exists?(tenant_name)

      # Verify table exists
      assert table_exists?(tenant_name, "first_table")

      # Verify both indexes exist
      assert index_exists?(tenant_name, "first_table", "first_table_name_index")
      assert index_exists?(tenant_name, "first_table", "name_concurrent_index")
    end

    test "migrate_tenant handles multiple concurrent indexes in one migration" do
      tenant_name = "test_tenant_multiple_concurrent"
      migration_file = Path.join(@temp_migrations_dir, "20250101000001_multiple_concurrent_indexes.exs")

      migration_content = """
      defmodule AshPostgres.TestRepo.TempTenantMigrations.MultipleConcurrentIndexes do
        use Ecto.Migration

        @disable_ddl_transaction true

        def up do
          create table(:multi_table, primary_key: false, prefix: prefix()) do
            add :id, :uuid, null: false, default: fragment("uuid_generate_v4()"), primary_key: true
            add :name, :text
            add :email, :text
            add :phone, :text
          end

          create index(:multi_table, [:email], concurrently: true, prefix: prefix())
          create index(:multi_table, [:phone], concurrently: true, prefix: prefix())
        end

        def down do
          drop index(:multi_table, [:phone], prefix: prefix())
          drop index(:multi_table, [:email], prefix: prefix())
          drop table(:multi_table, prefix: prefix())
        end
      end
      """

      File.write!(migration_file, migration_content)

      assert :ok = try_create_tenant(tenant_name, @temp_migrations_dir)

      assert schema_exists?(tenant_name)
      assert table_exists?(tenant_name, "multi_table")
      assert index_exists?(tenant_name, "multi_table", "multi_table_email_index")
      assert index_exists?(tenant_name, "multi_table", "multi_table_phone_index")
    end
  end

  # Helper functions

  defp try_create_tenant(tenant_name, migrations_path) do
    # Ensure `create_tenant!/2` will read migrations from the supplied path
    original_repo_env = Application.get_env(:ash_postgres, AshPostgres.TestRepo, [])

    try do
      Application.put_env(
        :ash_postgres,
        AshPostgres.TestRepo,
        Keyword.put(original_repo_env, :tenant_migrations_path, migrations_path)
      )

      MultiTenancy.create_tenant!(tenant_name, AshPostgres.TestRepo)
      :ok
    rescue
      e ->
        flunk("Failed to create tenant #{tenant_name}: #{inspect(e)}")
    after
      # Restore repo config even on failure
      Application.put_env(:ash_postgres, AshPostgres.TestRepo, original_repo_env)
    end
  end

  defp try_migrate_tenant(tenant_name, migrations_path) do
    try do
      MultiTenancy.migrate_tenant(tenant_name, AshPostgres.TestRepo, migrations_path)
      :ok
    rescue
      e ->
        flunk("Failed to migrate tenant #{tenant_name}: #{inspect(e)}")
    end
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
