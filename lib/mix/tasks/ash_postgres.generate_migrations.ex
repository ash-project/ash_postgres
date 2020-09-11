defmodule Mix.Tasks.AshPostgres.GenerateMigrations do
  @moduledoc """
  Generates migrations, and stores a snapshot of your resources.

  Options:

  * `apis` - a comma separated list of API modules, for which migrations will be generated
  * `snapshot_path` - a custom path to store the snapshots, defaults to "priv/resource_snapshots"
  * `migration_path` - a custom path to store the migrations, defaults to "priv".
    Migrations are stored in a folder for each repo, so `priv/repo_name/migrations`

  Flags:

  * `quiet` - messages for file creations will not be printed
  * `format` - files that are created will be formatted with the code formatter, defaults to true


  #### Conflicts/Multiple Resources

  The migration generator can support multiple schemas using the same table.
  It will raise on conflicts that it can't resolve, like the same field with different
  types. It will prompt to resolve conflicts that can be resolved with human input.
  For example, if you remove an attribute and add an attribute, it will ask you if you are renaming
  the column in question. If not, it will remove one column and add the other.

  Additionally, it lowers things to the database where possible:

  #### Defaults
  There are three anonymous functions that will translate to database-specific defaults currently:

  * `&Ash.uuid/0` - Only if `uuid-ossp` is in your `c:AshPostgres.Repo.installed_extensions()`
  * `&Ecto.UUID.generate/0` - Only if `uuid-ossp` is in your `c:AshPostgres.Repo.installed_extensions()`
  * `&DateTime.utc_now/0`

  Non-function default values will be dumped to their native type and inspected. This may not work for some types,
  and may require manual intervention/patches to the migration generator code.

  #### Identities

  Identities will cause the migration generator to generate unique constraints. If multiple
  resources target the same table, you will be asked to select the primary key, and any others
  will be added as unique constraints.
  """
  use Mix.Task

  @shortdoc "Generates migrations, and stores a snapshot of your resources"
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
