<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Migrations

## Tasks

Ash comes with its own tasks, and AshPostgres exposes lower level tasks that you can use if necessary. This guide shows the process using `ash.*` tasks, and the `ash_postgres.*` tasks are illustrated at the bottom.

## Basic Workflow

- Make resource changes
- Run `mix ash.codegen --dev` to generate a migration tagged as a `dev` migration, which will later be squashed and does not require a name.
- Run `mix ash.migrate` to run the migrations.
- Make some more resource changes.
- Once you're all done, run `mix ash.codegen add_a_combobulator`, using a good name for your changes to generate migrations and resource snapshots. This will **rollback** the dev migrations, and squash them into a the new named migration (or sometimes migrations).
- Run `mix ash.migrate` to run those migrations

The `--dev` workflow enables you to avoid having to think of a name for migrations while developing, and also enables some
upcoming workflows that will detect when code generation needs to be run on page load and will show you a button to generate
dev migrations and run them.

For more information on generating migrations, run `mix help ash_postgres.generate_migrations` (the underlying task that is called by `mix ash.migrate`)

> ### all_tenants/0 {: .info}
>
> If you have are using schema-based multitenancy, you will also need to define a `all_tenants/0` function in your repo module. See `AshPostgres.Repo` for more.

## Running Migrations in Production

Define a module similar to the following:

```elixir
defmodule MyApp.Release do
  @moduledoc """
Tasks that need to be executed in the released application (because mix is not present in releases).
  """
  @app :my_app
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  # only needed if you are using postgres multitenancy
  def migrate_tenants do
    load_app()

    for repo <- repos() do
      path = Ecto.Migrator.migrations_path(repo, "tenant_migrations")
      # This may be different for you if you are not using the default tenant migrations

      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn repo ->
            for tenant <- repo.all_tenants() do
              Ecto.Migrator.run(repo, path, :up, all: true, prefix: tenant)
            end
          end
        )
    end
  end

  # only needed if you are using postgres multitenancy
  def migrate_all do
    load_app()
    migrate()
    migrate_tenants()
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  # only needed if you are using postgres multitenancy
  def rollback_tenants(repo, version) do
    load_app()

    path = Ecto.Migrator.migrations_path(repo, "tenant_migrations")
    # This may be different for you if you are not using the default tenant migrations

    for tenant <- repo.all_tenants() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          &Ecto.Migrator.run(&1, path, :down,
            to: version,
            prefix: tenant
          )
        )
    end
  end

  defp repos do
    domains()
    |> Enum.flat_map(fn domain ->
      domain
      |> Ash.Domain.Info.resources()
      |> Enum.map(&AshPostgres.DataLayer.Info.repo/1)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.uniq()
  end

  defp domains do
    Application.fetch_env!(@app, :ash_domains)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

### AshPostgres-specific mix tasks

- `mix ash_postgres.generate_migrations`
- `mix ash_postgres.create`
- `mix ash_postgres.drop`
- `mix ash_postgres.migrate` (use `mix ash_postgres.migrate --tenants` to run tenant migrations)
- `mix ash_postgres.rollback` (use `mix ash_postgres.rollback --tenants` to rollback tenant migrations)
