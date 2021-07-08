defmodule AshPostgres.MixHelpers do
  @moduledoc false
  def apis(opts, args) do
    apps =
      if apps_paths = Mix.Project.apps_paths() do
        apps_paths |> Map.keys() |> Enum.sort()
      else
        [Mix.Project.config()[:app]]
      end

    configured_apis = Enum.flat_map(apps, &Application.get_env(&1, :ash_apis, []))

    apis =
      if opts[:apis] && opts[:apis] != "" do
        opts[:apis]
        |> Kernel.||("")
        |> String.split(",")
        |> Enum.flat_map(fn
          "" ->
            []

          api ->
            [Module.concat([api])]
        end)
      else
        configured_apis
      end

    Enum.map(apis, &ensure_compiled(&1, args))
  end

  def repos(opts, args) do
    opts
    |> apis(args)
    |> Enum.flat_map(&Ash.Api.resources/1)
    |> Enum.filter(&(Ash.DataLayer.data_layer(&1) == AshPostgres.DataLayer))
    |> Enum.map(&AshPostgres.repo(&1))
    |> Enum.uniq()
  end

  def delete_flag(args, arg) do
    case Enum.split_while(args, &(&1 != arg)) do
      {left, [_ | rest]} ->
        left ++ rest

      _ ->
        args
    end
  end

  def delete_arg(args, arg) do
    case Enum.split_while(args, &(&1 != arg)) do
      {left, [_, _ | rest]} ->
        left ++ rest

      _ ->
        args
    end
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

  def tenants(repo, opts) do
    tenants = repo.all_tenants()

    tenants =
      if is_binary(opts[:only_tenants]) do
        Enum.filter(String.split(opts[:only_tenants], ","), fn tenant ->
          tenant in tenants
        end)
      else
        tenants
      end

    if is_binary(opts[:except_tenants]) do
      reject = String.split(opts[:except_tenants], ",")

      Enum.reject(tenants, &(&1 in reject))
    else
      tenants
    end
  end

  def migrations_path(opts, repo) do
    opts[:migrations_path] || repo.config()[:migrations_path] || derive_migrations_path(repo)
  end

  def tenant_migrations_path(opts, repo) do
    opts[:migrations_path] || repo.config()[:tenant_migrations_path] ||
      derive_tenant_migrations_path(repo)
  end

  def derive_migrations_path(repo) do
    repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()

    "priv/"
    |> Path.join(repo_name)
    |> Path.join("migrations")
  end

  def derive_tenant_migrations_path(repo) do
    repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()

    "priv/"
    |> Path.join(repo_name)
    |> Path.join("tenant_migrations")
  end
end
