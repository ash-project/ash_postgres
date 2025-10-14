# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Verifiers.ValidateReferences do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    dsl
    |> AshPostgres.DataLayer.Info.references()
    |> Enum.each(fn reference ->
      if !Ash.Resource.Info.relationship(dsl, reference.relationship) do
        raise Spark.Error.DslError,
          path: [:postgres, :references, reference.relationship],
          module: Verifier.get_persisted(dsl, :module),
          message:
            "Found reference configuration for relationship `#{reference.relationship}`, but no such relationship exists",
          location: Spark.Dsl.Transformer.get_section_anno(dsl, [:postgres, :references])
      end
    end)

    :ok
  end
end
