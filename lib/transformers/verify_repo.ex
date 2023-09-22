defmodule AshPostgres.Transformers.VerifyRepo do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after_compile?, do: true

  def transform(dsl) do
    repo = Transformer.get_option(dsl, [:postgres], :repo)

    cond do
      match?({:error, _}, Code.ensure_compiled(repo)) ->
        {:error, "Could not find repo module #{repo}"}

      repo.__adapter__() != Ecto.Adapters.Postgres ->
        {:error, "Expected a repo using the postgres adapter `Ecto.Adapters.Postgres`"}

      true ->
        {:ok, dsl}
    end
  end
end
