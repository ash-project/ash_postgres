defmodule Mix.Tasks.AshPostgres.Gen.Resources do
  use Igniter.Mix.Task

  @shortdoc "Generates or updates resources based on a database schema"

  @doc """
  #{@shortdoc}

  ## Options

  - `repo`, `r` - The repo or repos to generate resources for, comma separated. Can be specified multiple times. Defaults to all repos.
  - `tables`, `t` - The tables to generate resources for, comma separated. Can be specified multiple times. Defaults to all tables non-`_*` tables
  - `skip-tables`, `s` - The tables to skip generating resources for, comma separated. Can be specified multiple times.
  - `snapshots-only`, `n` - Only generate snapshots for the generated resources, and not migraitons.
  - `domains` , 'd` - The domain to generate resources inside of. See the section on domains for more.
  """

  @impl Igniter.Mix.Task
  def info(_argv, _parent) do
    %Igniter.Mix.Task.Info{
      positional: [],
      schema: [
        repo: :keep,
        tables: :keep,
        skip_tables: :keep,
        snapshots_only: :boolean,
        domain: :keep
      ],
      aliases: [
        t: :tables,
        r: :repo,
        d: :domain,
        s: :skip_tables,
        n: :snapshots_only
      ]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter, argv) do
    Mix.Task.run("compile")

    options = options!(argv)

    repos =
      options[:repo] ||
        Mix.Project.config()[:app]
        |> Application.get_env(:ecto_repos, [])

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
          if Mix.shell().yes?(prompt) do
            Keyword.put(options, :no_migrations, false)
          else
            Keyword.put(options, :no_migrations, true)
          end

        migration_opts =
          if options[:snapshots_only] do
            ["--snapshots-only"]
          else
            []
          end

        igniter
        |> AshPostgres.ResourceGenerator.generate(repos, options)
        |> then(fn igniter ->
          if options[:no_migrations] do
            igniter
          else
            Igniter.add_task(igniter, "ash_postgres.generate_migrations", migration_opts)
          end
        end)
    end
  end
end
