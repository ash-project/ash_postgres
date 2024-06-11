defmodule Mix.Tasks.AshPostgres.Install do
  require Igniter.Common
  use Igniter.Mix.Task

  def igniter(igniter, argv) do
    repo = Igniter.Module.module_name("Repo")
    otp_app = Igniter.Application.app_name()

    igniter
    |> Igniter.Formatter.import_dep(:ash_postgres)
    |> setup_repo_module(otp_app, repo)
    |> configure_config(otp_app, repo)
    |> configure_dev(otp_app, repo)
    |> configure_test(otp_app, repo)
    |> configure_runtime(repo, otp_app)
    |> Igniter.Application.add_child(repo)
    |> Igniter.add_task("ash.codegen", ["install_ash_postgres"])
  end

  defp configure_config(igniter, otp_app, repo) do
    Igniter.Config.configure(
      igniter,
      "config.exs",
      otp_app,
      [:ecto_repos],
      [repo],
      fn zipper ->
        Igniter.Common.prepend_new_to_list(zipper, repo, &Igniter.Common.equal_modules?/2)
      end
    )
  end

  defp configure_runtime(igniter, otp_app, repo) do
    default_runtime = """
    import Config

    if config_env() == :prod do
      database_url =
        System.get_env("DATABASE_URL") ||
          raise \"\"\"
          environment variable DATABASE_URL is missing.
          For example: ecto://USER:PASS@HOST/DATABASE
          \"\"\"

      config #{inspect(otp_app)}, Helpdesk.Repo,
        url: database_url,
        pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
    end
    """

    igniter
    |> Igniter.create_or_update_elixir_file("config/runtime.exs", default_runtime, fn zipper ->
      if Igniter.Config.configures?(zipper, [repo, :url], otp_app) do
        zipper
      else
        patterns = [
          """
          if config_env() == :prod do
            __cursor__()
          end
          """,
          """
          if :prod == config_env() do
            __cursor__()
          end
          """
        ]

        zipper
        |> Igniter.Common.match_pattern_in_scope(patterns)
        |> case do
          {:ok, zipper} ->
            case Igniter.Common.move_to_function_call_in_current_scope(zipper, :=, 2, fn call ->
                   Igniter.Common.argument_matches_predicate?(
                     call,
                     0,
                     &match?({:database_url, _, Elixir}, &1)
                   )
                 end) do
              {:ok, zipper} ->
                zipper
                |> Igniter.Config.modify_configuration_code(
                  zipper,
                  [repo, :url],
                  otp_app,
                  {:database_url, [], Elixir}
                )
                |> Igniter.Config.modify_configuration_code(
                  zipper,
                  [repo, :pool_size],
                  otp_app,
                  quote do
                    String.to_integer(System.get_env("POOL_SIZE") || "10")
                  end
                )

              {:error, _error} ->
                Igniter.Common.add_code(zipper, """
                  database_url =
                    System.get_env("DATABASE_URL") ||
                      raise \"\"\"
                      environment variable DATABASE_URL is missing.
                      For example: ecto://USER:PASS@HOST/DATABASE
                      \"\"\"

                  config #{inspect(otp_app)}, Helpdesk.Repo,
                    url: database_url,
                    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
                """)
            end

          {:error, _error} ->
            Igniter.Common.add_code(zipper, """
            if config_env() == :prod do
              database_url =
                System.get_env("DATABASE_URL") ||
                  raise \"\"\"
                  environment variable DATABASE_URL is missing.
                  For example: ecto://USER:PASS@HOST/DATABASE
                  \"\"\"

              config #{inspect(otp_app)}, Helpdesk.Repo,
                url: database_url,
                pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
            end
            """)
        end
      end
    end)
  end

  defp configure_dev(igniter, otp_app, repo) do
    igniter
    |> Igniter.Config.configure_new("dev.exs", otp_app, [repo, :username], "postgres")
    |> Igniter.Config.configure_new("dev.exs", otp_app, [repo, :password], "postgres")
    |> Igniter.Config.configure_new("dev.exs", otp_app, [repo, :hostname], "localhost")
    |> Igniter.Config.configure_new("dev.exs", otp_app, [repo, :database], "#{otp_app}_dev")
    |> Igniter.Config.configure_new("dev.exs", otp_app, [repo, :port], 5432)
    |> Igniter.Config.configure_new(
      "dev.exs",
      otp_app,
      [repo, :show_sensitive_data_on_connection_error],
      true
    )
    |> Igniter.Config.configure_new("dev.exs", otp_app, [repo, :pool_size], 10)
  end

  defp configure_test(igniter, otp_app, repo) do
    database =
      {:<<>>, [],
       [
         "#{otp_app}_test",
         {:"::", [],
          [
            {{:., [], [Kernel, :to_string]}, [from_interpolation: true],
             [
               {{:., [], [{:__aliases__, [alias: false], [:System]}, :get_env]}, [],
                ["MIX_TEST_PARTITION"]}
             ]},
            {:binary, [], Elixir}
          ]}
       ]}
      |> Sourceror.to_string()
      |> Sourceror.parse_string!()

    igniter
    |> Igniter.Config.configure_new("test.exs", otp_app, [repo, :username], "postgres")
    |> Igniter.Config.configure_new("test.exs", otp_app, [repo, :password], "postgres")
    |> Igniter.Config.configure_new("test.exs", otp_app, [repo, :hostname], "localhost")
    |> Igniter.Config.configure_new("test.exs", otp_app, [repo, :database], {:code, database})
    |> Igniter.Config.configure_new("test.exs", otp_app, [repo, :port], 5432)
    |> Igniter.Config.configure_new("test.exs", otp_app, [repo, :pool], Ecto.Adapters.SQL.Sandbox)
    |> Igniter.Config.configure_new("test.exs", otp_app, [repo, :pool_size], 10)
  end

  defp setup_repo_module(igniter, otp_app, repo) do
    path = Igniter.Module.proper_location(repo)

    default_repo_contents =
      """
      defmodule #{inspect(repo)} do
        use AshPostgres.Repo, otp_app: #{inspect(otp_app)}

        def installed_extensions do
          # Add extensions here, and the migration generator will install them.
          ["ash-functions"]
        end
      end
      """

    igniter
    |> Igniter.create_or_update_elixir_file(path, default_repo_contents, fn zipper ->
      zipper
      |> set_otp_app(otp_app)
      |> Sourceror.Zipper.top()
      |> use_ash_postgres_instead_of_ecto()
      |> Sourceror.Zipper.top()
      |> add_installed_extensions_function()
      |> Sourceror.Zipper.top()
      |> remove_adapter_option()
    end)
  end

  defp use_ash_postgres_instead_of_ecto(zipper) do
    with {:ok, zipper} <- Igniter.Common.move_to_module_using(zipper, Ecto.Repo),
         {:ok, zipper} <- Igniter.Common.move_to_use(zipper, Ecto.Repo),
         {:ok, zipper} <-
           Igniter.Common.update_nth_argument(zipper, 0, fn _ ->
             AshPostgres.Repo
           end) do
      zipper
    else
      _ ->
        zipper
    end
  end

  defp remove_adapter_option(zipper) do
    with {:ok, zipper} <- Igniter.Common.move_to_module_using(zipper, Ecto.Repo),
         {:ok, zipper} <- Igniter.Common.move_to_use(zipper, Ecto.Repo),
         {:ok, zipper} <-
           Igniter.Common.update_nth_argument(zipper, 1, fn values_zipper ->
             values_zipper
             |> Igniter.Common.remove_keyword_key(:adapter)
           end) do
      zipper
    else
      _ ->
        zipper
    end
  end

  defp set_otp_app(zipper, otp_app) do
    with {:ok, zipper} <- Igniter.Common.move_to_module_using(zipper, Ecto.Repo),
         {:ok, zipper} <- Igniter.Common.move_to_use(zipper, Ecto.Repo),
         {:ok, zipper} <-
           Igniter.Common.update_nth_argument(zipper, 0, fn _ ->
             AshPostgres.Repo
           end),
         {:ok, zipper} <-
           Igniter.Common.update_nth_argument(zipper, 1, fn values_zipper ->
             values_zipper
             |> Igniter.Common.set_keyword_key(:otp_app, otp_app, fn x -> x end)
           end) do
      zipper
    else
      _ ->
        zipper
    end
  end

  defp add_installed_extensions_function(zipper) do
    with {:ok, zipper} <- Igniter.Common.move_to_module_using(zipper, Ecto.Repo) do
      Igniter.Common.add_code(zipper, """
      def installed_extensions do
        # Add extensions here, and the migration generator will install them.
        ["ash-functions"]
      end
      """)
    else
      _ ->
        zipper
    end
  end
end
