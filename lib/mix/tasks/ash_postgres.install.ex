defmodule Mix.Tasks.AshPostgres.Install do
  require Igniter.Common
  use Igniter.Mix.Task

  def igniter(igniter, argv) do
    repo = Igniter.Module.module_name("Repo")
    otp_app = Igniter.Application.app_name()

    igniter
    |> Igniter.Formatter.import_dep(:ash_postgres)
    |> setup_repo_module(otp_app, repo)
    |> Igniter.Config.configure("config.exs", :ash_postgres, [repo, :username], "postgres")
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
    |> Igniter.add_task("ash.codegen")
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
