defmodule Mix.Tasks.AshPostgres.GenerateMigrations do
  use Mix.Task

  @shortdoc "Generates migrations, and stores a snapshot of your resources"
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          apis: :string,
          snapshot_path: :string,
          migration_path: :string,
          init: :boolean,
          quiet: :boolean
        ]
      )

    apps =
      if apps_paths = Mix.Project.apps_paths() do
        # TODO: Use the proper ordering from Mix.Project.deps_apps
        # when we depend on Elixir v1.11+.
        apps_paths |> Map.keys() |> Enum.sort()
      else
        [Mix.Project.config()[:app]]
      end

    configured_apis = Enum.flat_map(apps, &Application.get_env(&1, :ash_apis, []))

    apis =
      opts[:apis]
      |> Kernel.||("")
      |> String.split(",")
      |> Enum.flat_map(fn
        "" ->
          []

        api ->
          [Module.concat([api])]
      end)
      |> Kernel.++(configured_apis)
      |> Enum.map(&ensure_compiled(&1, args))

    if apis == [] do
      raise "must supply the --apis argument, or set `config :my_app, apis: [...]` in config"
    end

    AshPostgres.MigrationGenerator.generate(apis, opts)
  end

  defp ensure_compiled(api, args) do
    # Copied from ecto's `ensure_repo`
    # TODO: Use only app.config when we depend on Elixir v1.11+.
    if Code.ensure_loaded?(Mix.Tasks.App.Config) do
      Mix.Task.run("app.config", args)
    else
      Mix.Task.run("loadpaths", args)
      "--no-compile" not in args && Mix.Task.run("compile", args)
    end

    case Code.ensure_compiled(api) do
      {:module, _} ->
        api

      {:error, error} ->
        Mix.raise("Could not load #{inspect(api)}, error: #{inspect(error)}. ")
    end
  end
end
