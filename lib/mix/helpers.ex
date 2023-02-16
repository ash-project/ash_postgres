defmodule AshPostgres.MixHelpers do
  @moduledoc false
  def apis!(opts, args) do
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

    apis
    |> Enum.map(&ensure_compiled(&1, args))
    |> case do
      [] ->
        raise "must supply the --apis argument, or set `config :my_app, ash_apis: [...]` in config"

      apis ->
        apis
    end
  end

  def repos!(opts, args) do
    apis = apis!(opts, args)

    resources =
      apis
      |> Enum.flat_map(&Ash.Api.Info.resources/1)
      |> Enum.filter(&(Ash.DataLayer.data_layer(&1) == AshPostgres.DataLayer))
      |> case do
        [] ->
          raise """
          No resources with `data_layer: AshPostgres.DataLayer` found in the apis #{Enum.map_join(apis, ",", &inspect/1)}.

          Must be able to find at least one resource with `data_layer: AshPostgres.DataLayer`.
          """

        resources ->
          resources
      end

    resources
    |> Enum.map(&AshPostgres.DataLayer.Info.repo(&1))
    |> Enum.uniq()
    |> case do
      [] ->
        raise """
        No repos could be found configured on the resources in the apis: #{Enum.map_join(apis, ",", &inspect/1)}

        At least one resource must have a repo configured.

        The following resources were found with `data_layer: AshPostgres.DataLayer`:

        #{Enum.map_join(resources, "\n", &"* #{inspect(&1)}")}
        """

      repos ->
        repos
    end
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
        |> Ash.Api.Info.resources()
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
    config = repo.config()
    priv = config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}"
    app = Keyword.fetch!(config, :otp_app)
    Application.app_dir(app, Path.join(priv, "migrations"))
  end

  def derive_tenant_migrations_path(repo) do
    config = repo.config()
    priv = config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}"
    app = Keyword.fetch!(config, :otp_app)
    Application.app_dir(app, Path.join(priv, "tenant_migrations"))
  end
end
