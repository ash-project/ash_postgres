defmodule AshPostgres.Verifiers.EnsureTableOrPolymorphic do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    if Verifier.get_option(dsl, [:postgres], :polymorphic?) ||
         Verifier.get_option(dsl, [:postgres], :table) do
      :ok
    else
      resource = Verifier.get_persisted(dsl, :module)

      raise Spark.Error.DslError,
        module: resource,
        message: """
        Must configure a table for #{inspect(resource)}.

        For example:

        ```elixir
        postgres do
          table "the_table"
          repo YourApp.Repo
        end
        ```
        """,
        path: [:postgres, :table]
    end
  end
end
