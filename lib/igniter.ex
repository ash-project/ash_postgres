defmodule AshPostgres.Igniter do
  @moduledoc "Codemods and utilities for working with AshPostgres & Igniter"

  @doc false
  def default_repo_contents(otp_app, name, opts \\ []) do
    min_pg_version = get_min_pg_version(name, opts)

    """
    use AshPostgres.Repo, otp_app: #{inspect(otp_app)}

    def min_pg_version do
      %Version{major: #{min_pg_version.major}, minor: #{min_pg_version.minor}, patch: #{min_pg_version.patch}}
    end

    def installed_extensions do
      # Add extensions here, and the migration generator will install them.
      ["ash-functions"]
    end
    """
  end

  def table(igniter, resource) do
    igniter
    |> Spark.Igniter.get_option(resource, [:postgres, :table])
    |> case do
      {igniter, {:ok, value}} when is_binary(value) or is_nil(value) ->
        {:ok, igniter, value}

      {igniter, _} ->
        {:error, igniter}
    end
  end

  def repo(igniter, resource) do
    igniter
    |> Spark.Igniter.get_option(resource, [:postgres, :repo])
    |> case do
      {igniter, {:ok, value}} when is_atom(value) ->
        {:ok, igniter, value}

      {igniter, _} ->
        {:error, igniter}
    end
  end

  def add_postgres_extension(igniter, repo_name, extension) do
    Igniter.Project.Module.find_and_update_module!(igniter, repo_name, fn zipper ->
      case Igniter.Code.Function.move_to_def(zipper, :installed_extensions, 0) do
        {:ok, zipper} ->
          case Igniter.Code.List.append_new_to_list(zipper, extension) do
            {:ok, zipper} ->
              {:ok, zipper}

            _ ->
              {:warning,
               "Could not add installed extension #{inspect(extension)} to #{inspect(repo_name)}.installed_extensions/0"}
          end

        _ ->
          zipper = Sourceror.Zipper.rightmost(zipper)

          code = """
          def installed_extensions do
            [#{inspect(extension)}]
          end
          """

          {:ok, Igniter.Code.Common.add_code(zipper, code)}
      end
    end)
  end

  def select_repo(igniter, opts \\ []) do
    label = Keyword.get(opts, :label, "Which repo should be used?")
    generate = Keyword.get(opts, :generate?, false)

    case list_repos(igniter) do
      {igniter, []} ->
        if generate do
          repo = Igniter.Project.Module.module_name(igniter, "Repo")
          otp_app = Igniter.Project.Application.app_name(igniter)

          igniter =
            Igniter.Project.Module.create_module(
              igniter,
              repo,
              default_repo_contents(otp_app, repo, opts),
              opts
            )

          {igniter, repo}
        else
          {igniter, nil}
        end

      {igniter, [repo]} ->
        {igniter, repo}

      {igniter, repos} ->
        {igniter, Owl.IO.select(repos, label: label, render_as: &inspect/1)}
    end
  end

  def list_repos(igniter) do
    Igniter.Project.Module.find_all_matching_modules(igniter, fn _mod, zipper ->
      move_to_repo_use(zipper) != :error
    end)
  end

  defp move_to_repo_use(zipper) do
    Igniter.Code.Function.move_to_function_call(zipper, :use, [1, 2], fn zipper ->
      Igniter.Code.Function.argument_equals?(
        zipper,
        0,
        AshPostgres.Repo
      )
    end)
  end

  @doc false
  def get_min_pg_version(name, opts) do
    if opts[:yes] do
      %Version{major: 13, minor: 0, patch: 0}
    else
      lead_in = """
      Generating #{inspect(name)}

      What is the minimum postgres version you will be using?

      AshPostgres uses this information when generating queries and migrations
      to choose the best available features for your version of postgres.
      """

      format_request =
        """
        Please enter the version in the format major.minor.patch (e.g. 13.4.0)

        Default: 16.0.0

        ❯
        """

      prompt =
        if opts[:invalid_loop?] do
          format_request
        else
          "#{lead_in}\n\n#{format_request}"
        end

      prompt
      |> String.trim_trailing()
      |> Mix.shell().prompt()
      |> String.trim()
      |> case do
        "" -> "16.0.0"
        input -> input
      end
      |> Version.parse()
      |> case do
        {:ok, version} -> version
        :error -> get_min_pg_version(name, Keyword.put(opts, :invalid_loop?, true))
      end
    end
  end
end
