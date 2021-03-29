defmodule AshPostgres.Transformers.EnsureTableOrPolymorphic do
  @moduledoc "Ensures that there is a table configured or the resource is polymorphic"
  use Ash.Dsl.Transformer

  def transform(resource, dsl) do
    if AshPostgres.polymorphic?(resource) || AshPostgres.table(resource) do
      {:ok, dsl}
    else
      {:error, "Non-polymorphic resources must have a postgres table configured."}
    end
  end
end
