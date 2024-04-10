defmodule Mix.Tasks.AshPostgres.Drop do
  use Mix.Task

  @shortdoc "Drops the repository storage for the repos in the specified (or configured) domains"
  @default_opts [force: false, force_drop: false]

  @aliases [
    f: :force,
    q: :quiet
  ]

  @switches [
    force: :boolean,
    force_drop: :boolean,
    quiet: :boolean,
    domains: :string,
    no_compile: :boolean,
    no_deps_check: :boolean
  ]

  @moduledoc """
  Drop the storage for the given repository.

  ## Examples

      mix ash_postgres.drop
      mix ash_postgres.drop -r MyApp.Repo1,MyApp.Repo2

  ## Command line options

    * `--domains` - the domains who's repos should be dropped
    * `-q`, `--quiet` - run the command quietly
    * `-f`, `--force` - do not ask for confirmation when dropping the database.
      Configuration is asked only when `:start_permanent` is set to true
      (typically in production)
    * `--force-drop` - force the database to be dropped even
      if it has connections to it (requires PostgreSQL 13+)
    * `--no-compile` - do not compile before dropping
    * `--no-deps-check` - do not compile before dropping
  """

  @doc false
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    opts = Keyword.merge(@default_opts, opts)

    repos =
      AshPostgres.Mix.Helpers.repos!(opts, args)
      |> Enum.filter(fn repo -> repo.drop? end)

    repo_args =
      Enum.flat_map(repos, fn repo ->
        ["-r", to_string(repo)]
      end)

    rest_opts = AshPostgres.Mix.Helpers.delete_arg(args, "--domains")

    Mix.Task.reenable("ecto.drop")
    Mix.Task.run("ecto.drop", repo_args ++ rest_opts)
  end
end
