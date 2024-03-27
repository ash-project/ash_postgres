defmodule AshPostgres.Verifiers.VerifyPostgresVersion do
  @moduledoc false
  use Spark.Dsl.Verifier

  def verify(dsl) do
    read_repo = AshPostgres.DataLayer.Info.repo(dsl, :read)
    mutate_repo = AshPostgres.DataLayer.Info.repo(dsl, :mutate)

    read_version =
      read_repo.pg_version() |> parse!(read_repo)

    mutation_version = mutate_repo.pg_version() |> parse!(mutate_repo)

    if Version.match?(read_version, ">= 14.0.0") && Version.match?(mutation_version, ">= 14.0.0") do
      :ok
    else
      {:error, "AshPostgres now only supports versions >= 14.0."}
    end
  end

  defp parse!(%Version{} = version, _repo) do
    version
  end

  defp parse!(version, repo) do
    Version.parse!(version)
  rescue
    e ->
      reraise ArgumentError,
              """
              Failed to parse version in `#{inspect(repo)}.pg_version()`: #{inspect(version)}

              Error: #{Exception.message(e)}
              """,
              __STACKTRACE__
  end
end
