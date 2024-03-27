defmodule AshPostgres.Verifiers.ValidateReferences do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    dsl
    |> AshPostgres.DataLayer.Info.references()
    |> Enum.each(fn reference ->
      unless Ash.Resource.Info.relationship(dsl, reference.relationship) do
        raise Spark.Error.DslError,
          path: [:postgres, :references, reference.relationship],
          module: Verifier.get_persisted(dsl, :module),
          message:
            "Found reference configuration for relationship `#{reference.relationship}`, but no such relationship exists"
      end
    end)

    :ok
  end
end
