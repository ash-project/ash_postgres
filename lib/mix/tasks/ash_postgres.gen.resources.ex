# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshPostgres.Gen.Resources do
    use Igniter.Mix.Task

    @example "mix ash_postgres.gen.resources MyApp.MyDomain"

    @shortdoc "Generates resources based on a database schema"

    @moduledoc """
    #{@shortdoc}

    ## Example

    `#{@example}`

    ## Domain

    The domain will be generated if it does not exist. If you aren't sure,
    we suggest using something like `MyApp.App`.

    ## Options

    - `repo`, `r` - The repo or repos to generate resources for, comma separated. Can be specified multiple times. Defaults to all repos.
    - `tables`, `t` - Defaults to `public.*`. The tables to generate resources for, comma separated. Can be specified multiple times. See the section on tables for more.
    - `skip-tables`, `s` - The tables to skip generating resources for, comma separated. Can be specified multiple times. See the section on tables for more. `schema_migrations` is always skipped.
    - `snapshots-only` - Only generate snapshots for the generated resources, and not migrations.
    - `extend`, `e` - Extension or extensions to apply to the generated resources. See `mix ash.patch.extend` for more.
    - `yes`, `y` - Answer yes (or skip) to all questions.
    - `default-actions` - Add default actions for each resource. Defaults to `true`.
    - `public` - Mark all attributes and relationships as `public? true`. Defaults to `true`.
    - `no-migrations` - Do not generate snapshots & migrations for the resources. Defaults to `false`.
    - `skip-unknown` - Skip any attributes with types that we don't have a corresponding Elixir type for, and relationships that we can't assume the name of.

    ## Tables

    When specifying tables to include with `--tables`, you can specify the table name, or the schema and table name separated by a period.
    For example, `users` will generate resources for the `users` table in the `public` schema, but `accounts.users` will generate resources for the `users` table in the `accounts` schema.

    To include all tables in a given schema, add a period only with no table name, i.e `schema.`, i.e `accounts.`.

    When skipping tables with `--skip-tables`, the same rules apply, except that the `schema.` format is not supported.
    """

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        positional: [:domain],
        example: @example,
        schema: [
          repo: :keep,
          yes: :boolean,
          tables: :keep,
          skip_tables: :keep,
          default_actions: :boolean,
          public: :boolean,
          extend: :keep,
          skip_unknown: :boolean,
          migrations: :boolean,
          snapshots_only: :boolean,
          domain: :keep
        ],
        aliases: [
          t: :tables,
          y: :boolean,
          r: :repo,
          e: :extend,
          d: :domain,
          s: :skip_tables
        ],
        defaults: [
          default_actions: true,
          migrations: true,
          public: true
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      Mix.Task.run("compile")

      options = igniter.args.options
      domain = igniter.args.positional.domain

      domain = Igniter.Project.Module.parse(domain)

      repos =
        case options[:repo] do
          [] ->
            Mix.Project.config()[:app]
            |> Application.get_env(:ecto_repos, [])

          repos ->
            repos
        end

      repos =
        repos
        |> List.wrap()
        |> Enum.map(fn v ->
          if is_binary(v) do
            Igniter.Project.Module.parse(v)
          else
            v
          end
        end)

      case repos do
        [] ->
          igniter
          |> Igniter.add_warning("No ecto repos configured.")

        repos ->
          Mix.shell().info("Generating resources from #{inspect(repos)}")

          prompt =
            """

            Would you like to generate migrations for the current structure? (recommended)

            If #{IO.ANSI.green()}yes#{IO.ANSI.reset()}:
              We will generate migrations based on the generated resources.
              You should then change your database name in your config, and
              run `mix ash.setup`.

              If you already have ecto migrations you'd like to use, run
              this command with `--snapshots-only`, in which case only resource
              snapshots will be generated.
              #{IO.ANSI.green()}
              Going forward, your resources will be the source of truth.#{IO.ANSI.reset()}
              #{IO.ANSI.red()}
              *WARNING*

              If you run `mix ash.reset` after this command without updating
              your config, you will be *deleting the database you just used to
              generate these resources*!#{IO.ANSI.reset()}

            If #{IO.ANSI.red()}no#{IO.ANSI.reset()}:

              We will not generate any migrations. This means you have migrations already that
              can get you from zero to the current starting point.
              #{IO.ANSI.yellow()}
              You will have to hand-write migrations from this point on.#{IO.ANSI.reset()}
            """

          options =
            cond do
              options[:migrations] == false ->
                Keyword.put(options, :no_migrations, true)

              options[:migrations] || options[:yes] || Mix.shell().yes?(prompt) ->
                Keyword.put(options, :no_migrations, false)

              true ->
                Keyword.put(options, :no_migrations, true)
            end

          migration_opts =
            if options[:snapshots_only] do
              ["--snapshots-only"]
            else
              []
            end

          igniter
          |> Igniter.compose_task("ash.gen.domain", [inspect(domain), "--ignore-if-exists"])
          |> AshPostgres.ResourceGenerator.generate(repos, domain, options)
          |> then(fn igniter ->
            if options[:no_migrations] do
              igniter
            else
              Igniter.add_task(igniter, "ash_postgres.generate_migrations", [
                "import_resources" | migration_opts
              ])
            end
          end)
      end
    end
  end
else
  defmodule Mix.Tasks.AshPostgres.Gen.Resources do
    @example "mix ash_postgres.gen.resource MyApp.MyDomain"

    @shortdoc "Generates resources based on a database schema"

    @moduledoc """
    #{@shortdoc}

    ## Example

    `#{@example}`
    """

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_postgres.gen.resources' requires igniter to be run.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
