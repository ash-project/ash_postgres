# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultiTenancy do
  @moduledoc false

  require Logger

  # sobelow_skip ["SQL.Query"]
  def create_tenant!(tenant_name, repo) do
    validate_tenant_name!(tenant_name)
    Ecto.Adapters.SQL.query!(repo, "CREATE SCHEMA IF NOT EXISTS \"#{tenant_name}\"", [])

    migrate_tenant(tenant_name, repo)
  end

  def migrate_tenant(tenant_name, repo, migrations_path \\ nil, after_file \\ nil) do
    tenant_migrations_path =
      migrations_path ||
        repo.config()[:tenant_migrations_path] || default_tenant_migration_path(repo)

    Ecto.Migration.SchemaMigration.ensure_schema_migrations_table!(
      repo,
      repo.config(),
      prefix: tenant_name
    )

    [tenant_migrations_path, "**", "*.exs"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
    |> then(fn files ->
      if after_file do
        files
        |> Enum.drop_while(fn file ->
          file != after_file
        end)
        |> Enum.drop(1)
      else
        files
      end
    end)
    |> Enum.map(&extract_migration_info/1)
    |> Enum.filter(& &1)
    |> Enum.map(&load_migration_with_file!/1)
    |> Enum.each(fn {version, mod, file} ->
      requires_no_transaction? = migration_requires_no_transaction?(mod)

      if requires_no_transaction? do
        # For migrations that require no transaction (e.g., concurrent indexes),
        # we need to ensure they run outside of any transaction.
        # Ecto.Migration.Runner.run will handle @disable_ddl_transaction correctly
        # if we're not already in a transaction, so we use a separate connection
        # or ensure we're not in a transaction.
        run_migration_without_transaction(repo, version, mod, tenant_name)
      else
        Ecto.Migration.Runner.run(
          repo,
          [],
          version,
          mod,
          :forward,
          :up,
          :up,
          all: true,
          prefix: tenant_name
        )

        Ecto.Migration.SchemaMigration.up(repo, repo.config(), version, prefix: tenant_name)
      end
    end)
  end

  # sobelow_skip ["SQL"]
  def rename_tenant(repo, old_name, new_name) do
    validate_tenant_name!(old_name)
    validate_tenant_name!(new_name)

    if to_string(old_name) != to_string(new_name) do
      Ecto.Adapters.SQL.query(repo, "ALTER SCHEMA \"#{old_name}\" RENAME TO \"#{new_name}\"")
    end

    :ok
  end

  defp load_migration_with_file!({version, _, file}) when is_binary(file) do
    loaded_modules = file |> compile_file() |> Enum.map(&elem(&1, 0))

    if mod = Enum.find(loaded_modules, &migration?/1) do
      {version, mod, file}
    else
      raise Ecto.MigrationError,
            "file #{Path.relative_to_cwd(file)} does not define an Ecto.Migration"
    end
  end


  defp compile_file(file) do
    AshPostgres.MigrationCompileCache.start_link()
    AshPostgres.MigrationCompileCache.compile_file(file)
  end

  defp migration?(mod) do
    function_exported?(mod, :__migration__, 0)
  end

  defp extract_migration_info(file) do
    base = Path.basename(file)

    case Integer.parse(Path.rootname(base)) do
      {integer, "_" <> name} -> {integer, name, file}
      _ -> nil
    end
  end

  defp validate_tenant_name!(tenant_name) do
    if !Regex.match?(tenant_name_regex(), tenant_name) do
      raise "Tenant name must match #{inspect(tenant_name_regex())}, got: #{tenant_name}"
    end
  end

  defp default_tenant_migration_path(repo) do
    repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()
    otp_app = repo.config()[:otp_app]

    :code.priv_dir(otp_app)
    |> Path.join(repo_name)
    |> Path.join("tenant_migrations")
  end

  defp tenant_name_regex do
    ~r/^[a-zA-Z0-9_-]+$/
  end

  # Check if a migration requires no transaction by examining the compiled module's
  # migration metadata. The module is already compiled at this point, so we ask
  # the module directly rather than reading the file. This also catches cases
  # where the attribute is set programmatically via Module.put_attribute/3.
  defp migration_requires_no_transaction?(mod) do
    if function_exported?(mod, :__migration__, 0) do
      migration_info = mod.__migration__()
      Map.get(migration_info, :disable_ddl_transaction, false)
    else
      false
    end
  end

  # Run a migration that requires no transaction outside of any transaction context
  defp run_migration_without_transaction(repo, version, mod, tenant_name) do
    # For migrations that require no transaction (e.g., concurrent indexes),
    # we need to ensure they run outside of any transaction.
    # Ecto.Migration.Runner.run respects @disable_ddl_transaction, but if we're
    # already in a transaction, PostgreSQL will still error.
    #
    # We use Ecto.Adapters.SQL.checkout/3 to get a fresh connection from the pool
    # that's not part of any transaction, ensuring the migration runs correctly.
    config = repo.config()

    Ecto.Adapters.SQL.checkout(repo, config, fn ->
      Ecto.Migration.Runner.run(
        repo,
        [],
        version,
        mod,
        :forward,
        :up,
        :up,
        all: true,
        prefix: tenant_name
      )

      Ecto.Migration.SchemaMigration.up(repo, config, version, prefix: tenant_name)
    end)
  end
end
