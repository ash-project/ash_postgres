# Migrations

## Tasks

Ash comes with its own tasks, and AshPostgres exposes lower level tasks that you can use if necessary. This guide shows the process using `ash.*` tasks, and the `ash_postgres.*` tasks are illustrated at the bottom.

## Basic Workflow

- Make resource changes
- Run `mix ash.codegen --name add_a_combobulator` to generate migrations and resource snapshots
- Run `mix ash.migrate` to run those migrations

For more information on generating migrations, run `mix help ash_postgres.generate_migrations` (the underlying task that is called by `mix ash.migrate`)

> ### list_tenants/0 {: .info}
>
> If you have are using schema-based multitenancy, you will also need to define a `list_tenants/0` function in your repo module. See `AshPostgres.Repo` for more.

### Regenerating Migrations

Often, you will run into a situation where you want to make a slight change to a resource after you've already generated and run migrations. If you are using git and would like to undo those changes, then regenerate the migrations, this script may prove useful:

```bash
#!/bin/bash

# Get count of untracked migrations
N_MIGRATIONS=$(git ls-files --others priv/repo/migrations | wc -l)

# Rollback untracked migrations
mix ash_postgres.rollback -n $N_MIGRATIONS

# Delete untracked migrations and snapshots
git ls-files --others priv/repo/migrations | xargs rm
git ls-files --others priv/resource_snapshots | xargs rm

# Regenerate migrations
mix ash.codegen --name $1

# Run migrations if flag
if echo $* | grep -e "-m" -q
then
  mix ash.migrate
fi
```

After saving this file to something like `regen.sh`, make it executable with `chmod +x regen.sh`. Now you can run it with `./regen.sh name_of_operation`. If you would like the migrations to automatically run after regeneration, add the `-m` flag: `./regen.sh name_of_operation -m`.

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
      repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()

      path =
        "priv/"
        |> Path.join(repo_name)
        |> Path.join("tenant_migrations")
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
    repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()

    path =
      "priv/"
      |> Path.join(repo_name)
      |> Path.join("tenant_migrations")
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
