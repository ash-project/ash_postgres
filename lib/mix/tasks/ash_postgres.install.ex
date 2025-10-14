# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshPostgres.Install do
    @moduledoc "Installs AshPostgres. Should be run with `mix igniter.install ash_postgres`"
    @shortdoc @moduledoc
    require Igniter.Code.Common
    require Igniter.Code.Function
    use Igniter.Mix.Task

    @impl true
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        schema: [
          yes: :boolean,
          repo: :string
        ],
        aliases: [
          y: :yes,
          r: :repo
        ]
      }
    end

    @impl true
    def igniter(igniter) do
      opts = igniter.args.options

      repo =
        case opts[:repo] do
          nil ->
            Igniter.Project.Module.module_name(igniter, "Repo")

          repo ->
            Igniter.Project.Module.parse(repo)
        end

      otp_app = Igniter.Project.Application.app_name(igniter)

      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_postgres)
      |> setup_aliases()
      |> setup_repo_module(otp_app, repo, opts)
      |> configure_config(otp_app, repo)
      |> configure_dev(otp_app, repo)
      |> configure_runtime(otp_app, repo)
      |> configure_test(otp_app, repo)
      |> setup_data_case()
      |> Igniter.Project.Application.add_new_child(repo,
        after: fn mod ->
          case Module.split(mod) do
            [_, "Telemetry"] -> true
            _ -> false
          end
        end
      )
      |> Spark.Igniter.prepend_to_section_order(:"Ash.Resource", [:postgres])
      |> Ash.Igniter.codegen("initialize")
    end

    defp setup_aliases(igniter) do
      is_ecto_setup = &Igniter.Code.Common.nodes_equal?(&1, "ecto.setup")

      is_ecto_create_or_migrate =
        fn zipper ->
          Igniter.Code.Common.nodes_equal?(zipper, "ecto.create --quiet") or
            Igniter.Code.Common.nodes_equal?(zipper, "ecto.create") or
            Igniter.Code.Common.nodes_equal?(zipper, "ecto.migrate --quiet") or
            Igniter.Code.Common.nodes_equal?(zipper, "ecto.migrate")
        end

      igniter
      |> Igniter.Project.TaskAliases.modify_existing_alias(
        "test",
        &Igniter.Code.List.remove_from_list(&1, is_ecto_create_or_migrate)
      )
      |> Igniter.Project.TaskAliases.modify_existing_alias(
        "test",
        &Igniter.Code.List.replace_in_list(
          &1,
          is_ecto_setup,
          Sourceror.parse_string!("\"ash.setup\"")
        )
      )
      |> Igniter.Project.TaskAliases.add_alias("test", ["ash.setup --quiet", "test"],
        if_exists: {:prepend, "ash.setup --quiet"}
      )
      |> run_seeds_on_setup()
    end

    defp run_seeds_on_setup(igniter) do
      if Igniter.exists?(igniter, "priv/repo/seeds.exs") do
        igniter
        |> Igniter.Project.TaskAliases.add_alias("setup", "ash.setup",
          if_exists: {:replace_or_append, "ecto.setup", "ash.setup"}
        )
        |> Igniter.Project.TaskAliases.add_alias("setup", "run priv/repo/seeds.exs",
          if_exists: :append
        )
      else
        Igniter.Project.TaskAliases.add_alias(igniter, "setup", "ash.setup")
      end
    end

    defp configure_config(igniter, otp_app, repo) do
      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        otp_app,
        [:ecto_repos],
        [repo],
        updater: fn zipper ->
          Igniter.Code.List.prepend_new_to_list(
            zipper,
            repo
          )
        end
      )
    end

    defp configure_runtime(igniter, otp_app, repo) do
      if Igniter.Project.Config.configures_key?(igniter, "runtime.exs", otp_app, [repo]) do
        igniter
      else
        default_runtime = """
        import Config

        if config_env() == :prod do
          database_url =
            System.get_env("DATABASE_URL") ||
              raise \"\"\"
              environment variable DATABASE_URL is missing.
              For example: ecto://USER:PASS@HOST/DATABASE
              \"\"\"

          config #{inspect(otp_app)}, #{inspect(repo)},
            url: database_url,
            pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
        end
        """

        igniter
        |> Igniter.create_or_update_elixir_file(
          "config/runtime.exs",
          default_runtime,
          fn zipper ->
            if Igniter.Project.Config.configures_key?(zipper, otp_app, [repo]) do
              {:ok, zipper}
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
              |> Igniter.Code.Common.move_to_cursor_match_in_scope(patterns)
              |> case do
                {:ok, zipper} ->
                  if Igniter.Project.Config.configures_key?(zipper, otp_app, [repo]) do
                    {:ok, zipper}
                  else
                    case Igniter.Code.Function.move_to_function_call_in_current_scope(
                           zipper,
                           :=,
                           2,
                           fn call ->
                             Igniter.Code.Function.argument_matches_pattern?(
                               call,
                               0,
                               {:database_url, _, ctx} when is_atom(ctx)
                             )
                           end
                         ) do
                      {:ok, _zipper} ->
                        zipper
                        |> modify_configuration_code(
                          [repo, :url],
                          otp_app,
                          {:database_url, [], nil}
                        )
                        |> modify_configuration_code(
                          [repo, :pool_size],
                          otp_app,
                          Sourceror.parse_string!("""
                          String.to_integer(System.get_env("POOL_SIZE") || "10")
                          """)
                        )
                        |> then(&{:ok, &1})

                      _ ->
                        Igniter.Code.Common.add_code(zipper, """
                          database_url =
                            System.get_env("DATABASE_URL") ||
                              raise \"\"\"
                              environment variable DATABASE_URL is missing.
                              For example: ecto://USER:PASS@HOST/DATABASE
                              \"\"\"

                          config #{inspect(otp_app)}, #{inspect(repo)},
                            url: database_url,
                            pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
                        """)
                    end
                  end

                :error ->
                  Igniter.Code.Common.add_code(zipper, """
                  if config_env() == :prod do
                    database_url =
                      System.get_env("DATABASE_URL") ||
                        raise \"\"\"
                        environment variable DATABASE_URL is missing.
                        For example: ecto://USER:PASS@HOST/DATABASE
                        \"\"\"

                    config #{inspect(otp_app)}, #{inspect(repo)},
                      url: database_url,
                      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
                  end
                  """)
              end
            end
          end
        )
      end
    end

    defp modify_configuration_code(zipper, path, otp_app, code) do
      case Igniter.Project.Config.modify_config_code(zipper, path, otp_app, code) do
        {:ok, zipper} -> zipper
        _ -> zipper
      end
    end

    defp configure_dev(igniter, otp_app, repo) do
      if Igniter.Project.Config.configures_key?(igniter, "dev.exs", otp_app, [repo]) do
        igniter
      else
        igniter
        |> Igniter.Project.Config.configure_new("dev.exs", otp_app, [repo, :username], "postgres")
        |> Igniter.Project.Config.configure_new("dev.exs", otp_app, [repo, :password], "postgres")
        |> Igniter.Project.Config.configure_new(
          "dev.exs",
          otp_app,
          [repo, :hostname],
          "localhost"
        )
        |> Igniter.Project.Config.configure_new(
          "dev.exs",
          otp_app,
          [repo, :database],
          "#{otp_app}_dev"
        )
        |> Igniter.Project.Config.configure_new(
          "dev.exs",
          otp_app,
          [repo, :show_sensitive_data_on_connection_error],
          true
        )
        |> Igniter.Project.Config.configure_new("dev.exs", otp_app, [repo, :pool_size], 10)
      end
    end

    defp configure_test(igniter, otp_app, repo) do
      if Igniter.Project.Config.configures_key?(igniter, "test.exs", otp_app, [repo]) do
        igniter
      else
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
        |> Igniter.Project.Config.configure_new(
          "test.exs",
          otp_app,
          [repo, :username],
          "postgres"
        )
        |> Igniter.Project.Config.configure_new(
          "test.exs",
          otp_app,
          [repo, :password],
          "postgres"
        )
        |> Igniter.Project.Config.configure_new(
          "test.exs",
          otp_app,
          [repo, :hostname],
          "localhost"
        )
        |> Igniter.Project.Config.configure_new(
          "test.exs",
          otp_app,
          [repo, :database],
          {:code, database}
        )
        |> Igniter.Project.Config.configure_new(
          "test.exs",
          otp_app,
          [repo, :pool],
          Ecto.Adapters.SQL.Sandbox
        )
        |> Igniter.Project.Config.configure_new("test.exs", otp_app, [repo, :pool_size], 10)
      end
      |> Igniter.Project.Config.configure_new("test.exs", :ash, [:disable_async?], true)
    end

    defp setup_data_case(igniter) do
      module_name = Igniter.Project.Module.module_name(igniter, "DataCase")

      default_data_case_contents = ~s|
    @moduledoc """
    This module defines the setup for tests requiring
    access to the application's data layer.

    You may define functions here to be used as helpers in
    your tests.

    Finally, if the test case interacts with the database,
    we enable the SQL sandbox, so changes done to the database
    are reverted at the end of every test. If you are using
    PostgreSQL, you can even run database tests asynchronously
    by setting `use #{inspect(module_name)}, async: true`, although
    this option is not recommended for other databases.
    """

    use ExUnit.CaseTemplate

    using do
      quote do
        alias #{inspect(Igniter.Project.Module.module_name(igniter, "Repo"))}

        import Ecto
        import Ecto.Changeset
        import Ecto.Query
        import #{inspect(Igniter.Project.Module.module_name(igniter, "DataCase"))}
      end
    end

    setup tags do
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(#{inspect(Igniter.Project.Module.module_name(igniter, "Repo"))}, shared: not tags[:async])
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
      :ok
    end
    |

      igniter
      |> Igniter.Project.Module.find_and_update_or_create_module(
        module_name,
        default_data_case_contents,
        # do nothing if already exists
        fn zipper -> {:ok, zipper} end,
        path: Igniter.Project.Module.proper_location(igniter, module_name, :test_support)
      )
    end

    defp setup_repo_module(igniter, otp_app, repo, opts) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, repo)

      if exists? do
        Igniter.Project.Module.find_and_update_module!(
          igniter,
          repo,
          fn zipper ->
            case Igniter.Code.Module.move_to_use(zipper, Ecto.Repo) do
              {:ok, _} ->
                {:ok,
                 zipper
                 |> set_otp_app(otp_app)
                 |> Sourceror.Zipper.top()
                 |> use_ash_postgres_instead_of_ecto()
                 |> Sourceror.Zipper.top()
                 |> remove_adapter_option()}

              _ ->
                case Igniter.Code.Module.move_to_use(zipper, AshPostgres.Repo) do
                  {:ok, _} ->
                    {:ok, zipper}

                  _ ->
                    {:error,
                     """
                     Repo module #{inspect(repo)} existed, but was not an `Ecto.Repo` or an `AshPostgres.Repo`.

                     Please re-run the AshPostgres installer with the `--repo` option to specify a repo.
                     """}
                end
            end
          end
        )
      else
        {min_pg_version, notice} = min_pg_version_and_notice(repo)

        Igniter.Project.Module.create_module(
          igniter,
          repo,
          AshPostgres.Igniter.default_repo_contents(
            otp_app,
            Keyword.put(opts, :min_pg_version, min_pg_version)
          )
        )
        |> Igniter.add_notice(notice)
      end
      |> Igniter.Project.Module.find_and_update_module!(
        repo,
        &configure_installed_extensions_function/1
      )
      |> Igniter.Project.Module.find_and_update_module!(
        repo,
        &configure_prefer_transaction_function/1
      )
      |> then(fn igniter ->
        {min_pg_version, notice} = min_pg_version_and_notice(repo)

        igniter
        |> Igniter.Project.Module.find_and_update_module!(
          repo,
          &configure_min_pg_version_function(
            &1,
            repo,
            min_pg_version || Version.parse!("16.0.0"),
            opts
          )
        )
        |> Igniter.add_notice(notice)
      end)
    end

    defp min_pg_version_and_notice(repo) do
      min_pg_version = get_min_pg_version()

      notice =
        if min_pg_version do
          """
          A `min_pg_version/0` function has been defined
          in `#{inspect(repo)}` as `#{min_pg_version}`.

          This was based on running `postgres -V`.

          You may wish to update this configuration. It should
          be set to the lowest version that your application
          expects to be run against.
          """
        else
          """
          A `min_pg_version/0` function has been defined in
          `#{inspect(repo)}` automatically.

          You may wish to update this configuration. It should
          be set to the lowest version that your application
          expects to be run against.
          """
        end

      {min_pg_version, notice}
    end

    defp get_min_pg_version do
      case System.cmd("postgres", ["-V"]) do
        {"postgres (PostgreSQL) " <> version_and_text, 0} ->
          version_and_text
          |> String.split(~r/\s+/, parts: 2, trim: true)
          |> Enum.at(0)
          |> String.split(".", trim: true)
          |> case do
            [major, minor, patch | _] -> Version.parse!("#{major}.#{minor}.#{patch}")
            [major, minor] -> Version.parse!("#{major}.#{minor}.0")
            [major] -> Version.parse!("#{major}.0.0")
            _ -> nil
          end

        _ ->
          nil
      end
    rescue
      _ ->
        nil
    end

    defp use_ash_postgres_instead_of_ecto(zipper) do
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, Ecto.Repo),
           {:ok, zipper} <- Igniter.Code.Module.move_to_use(zipper, Ecto.Repo),
           {:ok, zipper} <-
             Igniter.Code.Function.update_nth_argument(zipper, 0, fn zipper ->
               {:ok, Igniter.Code.Common.replace_code(zipper, AshPostgres.Repo)}
             end) do
        zipper
      else
        _ ->
          zipper
      end
    end

    defp remove_adapter_option(zipper) do
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, AshPostgres.Repo),
           {:ok, zipper} <- Igniter.Code.Module.move_to_use(zipper, AshPostgres.Repo),
           {:ok, zipper} <-
             Igniter.Code.Function.update_nth_argument(zipper, 1, fn values_zipper ->
               Igniter.Code.Keyword.remove_keyword_key(values_zipper, :adapter)
             end) do
        zipper
      else
        _ ->
          zipper
      end
    end

    defp set_otp_app(zipper, otp_app) do
      with {:ok, zipper} <- Igniter.Code.Module.move_to_module_using(zipper, AshPostgres.Repo),
           {:ok, zipper} <- Igniter.Code.Module.move_to_use(zipper, AshPostgres.Repo),
           {:ok, zipper} <-
             Igniter.Code.Function.update_nth_argument(zipper, 0, fn zipper ->
               {:ok, Igniter.Code.Common.replace_code(zipper, AshPostgres.Repo)}
             end),
           {:ok, zipper} <-
             Igniter.Code.Function.update_nth_argument(zipper, 1, fn values_zipper ->
               values_zipper
               |> Igniter.Code.Keyword.set_keyword_key(:otp_app, otp_app, fn x -> {:ok, x} end)
             end) do
        zipper
      else
        _ ->
          zipper
      end
    end

    defp configure_installed_extensions_function(zipper) do
      case Igniter.Code.Function.move_to_def(zipper, :installed_extensions, 0) do
        {:ok, zipper} ->
          case Igniter.Code.Common.move_right(zipper, &Igniter.Code.List.list?/1) do
            {:ok, zipper} ->
              Igniter.Code.List.append_new_to_list(zipper, "ash-functions")

            :error ->
              {:error, "installed_extensions/0 doesn't return a list"}
          end

        _ ->
          {:ok,
           Igniter.Code.Common.add_code(zipper, """
           @impl true
           def installed_extensions do
             # Add extensions here, and the migration generator will install them.
             ["ash-functions"]
           end
           """)}
      end
    end

    defp configure_prefer_transaction_function(zipper) do
      case Igniter.Code.Function.move_to_def(zipper, :prefer_transaction?, 0) do
        {:ok, zipper} ->
          {:ok, zipper}

        _ ->
          {:ok,
           Igniter.Code.Common.add_code(zipper, """
           # Don't open unnecessary transactions
           # will default to `false` in 4.0
           @impl true
           def prefer_transaction? do
             false
           end
           """)}
      end
    end

    defp configure_min_pg_version_function(zipper, _repo, version, _opts) do
      case Igniter.Code.Function.move_to_def(zipper, :min_pg_version, 0) do
        {:ok, zipper} ->
          {:ok, zipper}

        _ ->
          {:ok,
           Igniter.Code.Common.add_code(zipper, """
           @impl true
           def min_pg_version do
             %Version{major: #{version.major}, minor: #{version.minor}, patch: #{version.patch}}
           end
           """)}
      end
    end
  end
else
  defmodule Mix.Tasks.AshPostgres.Install do
    @moduledoc "Installs AshPostgres into a project. Should be called with `mix igniter.install ash_postgres`"

    @shortdoc @moduledoc

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_postgres.install' requires igniter to be run.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
