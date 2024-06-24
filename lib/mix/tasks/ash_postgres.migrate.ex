defmodule Mix.Tasks.AshPostgres.Migrate do
  use Mix.Task

  import AshPostgres.Mix.Helpers,
    only: [migrations_path: 2, tenant_migrations_path: 2, tenants: 2]

  @shortdoc "Runs the repository migrations for all repositories in the provided (or congigured) domains"

  @aliases [
    n: :step
  ]

  @switches [
    all: :boolean,
    tenants: :boolean,
    step: :integer,
    to: :integer,
    quiet: :boolean,
    prefix: :string,
    pool_size: :integer,
    log_sql: :boolean,
    strict_version_order: :boolean,
    domains: :string,
    no_compile: :boolean,
    no_deps_check: :boolean,
    migrations_path: :keep,
    only_tenants: :string,
    except_tenants: :string
  ]

  @moduledoc """
  Runs the pending migrations for the given repository.

  Migrations are expected at "priv/YOUR_REPO/migrations" directory
  of the current application (or `tenant_migrations` for multitenancy),
  where "YOUR_REPO" is the last segment
  in your repository name. For example, the repository `MyApp.Repo`
  will use "priv/repo/migrations". The repository `Whatever.MyRepo`
  will use "priv/my_repo/migrations".

  This task runs all pending migrations by default. To migrate up to a
  specific version number, supply `--to version_number`. To migrate a
  specific number of times, use `--step n`.

  If you have multiple repos and you want to run a single migration and/or
  migrate them to different points, you will need to use the ecto specific task,
  `mix ecto.migrate` and provide your repo name.

  If a repository has not yet been started, one will be started outside
  your application supervision tree and shutdown afterwards.

  ## Examples

      mix ash_postgres.migrate
      mix ash_postgres.migrate --domains MyApp.Domain1,MyApp.Domain2

      mix ash_postgres.migrate -n 3
      mix ash_postgres.migrate --step 3

      mix ash_postgres.migrate --to 20080906120000

  ## Command line options

    * `--domains` - the domains who's repos should be migrated

    * `--tenants` - Run the tenant migrations

    * `--only-tenants` - in combo with `--tenants`, only runs migrations for the provided tenants, e.g `tenant1,tenant2,tenant3`

    * `--except-tenants` - in combo with `--tenants`, does not run migrations for the provided tenants, e.g `tenant1,tenant2,tenant3`

    * `--all` - run all pending migrations

    * `--step`, `-n` - run n number of pending migrations

    * `--to` - run all migrations up to and including version

    * `--quiet` - do not log migration commands

    * `--prefix` - the prefix to run migrations on. This is ignored if `--tenants` is provided.

    * `--pool-size` - the pool size if the repository is started only for the task (defaults to 2)

    * `--log-sql` - log the raw sql migrations are running

    * `--strict-version-order` - abort when applying a migration with old timestamp

    * `--no-compile` - does not compile applications before migrating

    * `--no-deps-check` - does not check depedendencies before migrating

    * `--migrations-path` - the path to load the migrations from, defaults to
      `"priv/repo/migrations"`. This option may be given multiple times in which case the migrations
      are loaded from all the given directories and sorted as if they were in the same one.

      Note, if you have migrations paths e.g. `a/` and `b/`, and run
      `mix ecto.migrate --migrations-path a/`, the latest migrations from `a/` will be run (even
      if `b/` contains the overall latest migrations.)
  """

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    repos = AshPostgres.Mix.Helpers.repos!(opts, args)

    rest_opts =
      args
      |> AshPostgres.Mix.Helpers.delete_arg("--domains")
      |> AshPostgres.Mix.Helpers.delete_arg("--migrations-path")
      |> AshPostgres.Mix.Helpers.delete_flag("--tenants")
      |> AshPostgres.Mix.Helpers.delete_arg("--only-tenants")
      |> AshPostgres.Mix.Helpers.delete_arg("--except-tenants")

    Mix.Task.reenable("ecto.migrate")

    if opts[:tenants] do
      for repo <- repos do
        Ecto.Migrator.with_repo(repo, fn repo ->
          for tenant <- tenants(repo, opts) do
            rest_opts = AshPostgres.Mix.Helpers.delete_arg(rest_opts, "--prefix")

            Mix.Task.run(
              "ecto.migrate",
              ["-r", to_string(repo)] ++
                rest_opts ++
                ["--prefix", tenant, "--migrations-path", tenant_migrations_path(opts, repo)]
            )

            Mix.Task.reenable("ecto.migrate")
          end
        end)
      end
    else
      for repo <- repos do
        Mix.Task.run(
          "ecto.migrate",
          ["-r", to_string(repo)] ++
            rest_opts ++
            ["--migrations-path", migrations_path(opts, repo)]
        )

        Mix.Task.reenable("ecto.migrate")
      end
    end
  end
end
