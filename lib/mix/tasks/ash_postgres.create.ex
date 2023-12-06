defmodule Mix.Tasks.AshPostgres.Create do
  use Mix.Task

  @shortdoc "Creates the repository storage"

  @switches [
    quiet: :boolean,
    apis: :string,
    no_compile: :boolean,
    no_deps_check: :boolean
  ]

  @aliases [
    q: :quiet
  ]

  @moduledoc """
  Create the storage for repos in all resources for the given (or configured) apis.

  ## Examples

      mix ash_postgres.create
      mix ash_postgres.create --apis MyApp.Api1,MyApp.Api2

  ## Command line options

    * `--apis` - the apis who's repos you want to migrate.
    * `--quiet` - do not log output
    * `--no-compile` - do not compile before creating
    * `--no-deps-check` - do not compile before creating
  """

  @doc false
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    repos = AshPostgres.MixHelpers.repos!(opts, args)

    repo_args =
      Enum.flat_map(repos, fn repo ->
        ["-r", to_string(repo)]
      end)

    rest_opts = AshPostgres.MixHelpers.delete_arg(args, "--apis")

    Mix.Task.reenable("ecto.create")
    Mix.Task.run("ecto.create", repo_args ++ rest_opts)
  end
end
