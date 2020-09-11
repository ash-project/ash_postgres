defmodule Mix.Tasks.AshPostgres.GenerateMigrations do
  @description "Generates migrations, and stores a snapshot of your resources"
  @moduledoc @description
  use Mix.Task

  @shortdoc @description
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          apis: :string,
          snapshot_path: :string,
          migration_path: :string,
          quiet: :boolean,
          format: :boolean
        ]
      )

    apps =
      if apps_paths = Mix.Project.apps_paths() do
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
    if Code.ensure_loaded?(Mix.Tasks.App.Config) do
      Mix.Task.run("app.config", args)
    else
      Mix.Task.run("loadpaths", args)
      "--no-compile" not in args && Mix.Task.run("compile", args)
    end

    case Code.ensure_compiled(api) do
      {:module, _} ->
        api
        |> Ash.Api.resources()
        |> Enum.each(&Code.ensure_compiled/1)

        # TODO: We shouldn't need to make sure that the resources are compiled

        api

      {:error, error} ->
        Mix.raise("Could not load #{inspect(api)}, error: #{inspect(error)}. ")
    end
  end
end
