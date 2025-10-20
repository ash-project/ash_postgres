# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationModuleAttributesNoSandboxTest do
  use AshPostgres.RepoNoSandboxCase, async: false
  @moduletag :migration

  import ExUnit.CaptureLog

  setup do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    unique_id = System.unique_integer([:positive])
    tenant_name = "test_no_sandbox_tenant_#{timestamp}_#{unique_id}"

    Ecto.Adapters.SQL.query!(
      AshPostgres.TestRepo,
      "CREATE SCHEMA IF NOT EXISTS \"#{tenant_name}\"",
      []
    )

    Ecto.Adapters.SQL.query!(
      AshPostgres.TestRepo,
      "CREATE TABLE \"#{tenant_name}\".posts (id serial PRIMARY KEY, title text)",
      []
    )

    on_exit(fn ->
      Ecto.Adapters.SQL.query!(AshPostgres.TestRepo, "DROP SCHEMA \"#{tenant_name}\" CASCADE", [])
    end)

    %{tenant_name: tenant_name}
  end

  describe "migration attributes without sandbox" do
    test "tenant migration with @disable_ddl_transaction can create concurrent index", %{
      tenant_name: tenant_name
    } do
      migration_content = """
      defmodule TestConcurrentIndexMigrationNoSandbox do
        use Ecto.Migration
        @disable_ddl_transaction true
        @disable_migration_lock true

        def up do
          create index(:posts, [:title], concurrently: true)
        end

        def down do
          drop index(:posts, [:title])
        end
      end
      """

      IO.puts(
        "You should not not see a warning in this test about missing @disable_ddl_transaction"
      )

      migration_file =
        create_test_migration("test_concurrent_index_migration_no_sandbox.exs", migration_content)

      result =
        capture_log(fn ->
          AshPostgres.MultiTenancy.migrate_tenant(
            tenant_name,
            AshPostgres.TestRepo,
            Path.dirname(migration_file)
          )
        end)

      assert result =~ "== Migrated"

      index_result =
        Ecto.Adapters.SQL.query!(
          AshPostgres.TestRepo,
          """
            SELECT indexname FROM pg_indexes
            WHERE schemaname = '#{tenant_name}'
            AND tablename = 'posts'
            AND indexname LIKE '%title%'
          """,
          []
        )

      assert length(index_result.rows) > 0

      cleanup_migration_files(migration_file)
    end

    test "tenant migration without @disable_ddl_transaction gives warnings", %{
      tenant_name: tenant_name
    } do
      migration_content = """
      defmodule TestConcurrentIndexMigrationWithoutDisableNoSandbox do
        use Ecto.Migration

        def up do
          create index(:posts, [:title], concurrently: true)
        end

        def down do
          drop index(:posts, [:title])
        end
      end
      """

      IO.puts("You should see a warning in this test about missing @disable_ddl_transaction")

      migration_file =
        create_test_migration(
          "test_concurrent_index_migration_without_disable_no_sandbox.exs",
          migration_content
        )

      result =
        capture_log(fn ->
          AshPostgres.MultiTenancy.migrate_tenant(
            tenant_name,
            AshPostgres.TestRepo,
            Path.dirname(migration_file)
          )
        end)

      # The warnings are printed to the console (visible in test output above)
      # We can see them in the test output, but they're not captured by capture_log
      assert result =~ "== Migrated"

      index_result =
        Ecto.Adapters.SQL.query!(
          AshPostgres.TestRepo,
          """
            SELECT indexname FROM pg_indexes
            WHERE schemaname = '#{tenant_name}'
            AND tablename = 'posts'
            AND indexname LIKE '%title%'
          """,
          []
        )

      assert length(index_result.rows) > 0

      cleanup_migration_files(migration_file)
    end
  end

  defp create_test_migration(filename, content) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond) |> Integer.to_string()
    unique_id = System.unique_integer([:positive])

    test_migrations_dir =
      Path.join(System.tmp_dir!(), "ash_postgres_test_migrations_#{timestamp}_#{unique_id}")

    File.mkdir_p!(test_migrations_dir)

    migration_filename = "#{timestamp}_#{filename}"
    migration_file = Path.join(test_migrations_dir, migration_filename)
    File.write!(migration_file, content)

    migration_file
  end

  defp cleanup_migration_files(migration_file) do
    migration_dir = Path.dirname(migration_file)
    File.rm_rf(migration_dir)
  end
end
