defmodule AshPostgres.Transformers.EnsureTableOrPolymorphic do
  @moduledoc "Ensures that there is a table configured or the resource is polymorphic"
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl) do
    if Transformer.get_option(dsl, [:postgres], :polymorphic?) ||
         Transformer.get_option(dsl, [:postgres], :table) do
      {:ok, dsl}
    else
      {:error, "Non-polymorphic resources must have a postgres table configured."}
    end
  end
end
