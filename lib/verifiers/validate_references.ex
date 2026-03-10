# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
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
      relationship = Ash.Resource.Info.relationship(dsl, reference.relationship)

      cond do
        is_nil(relationship) ->
          raise Spark.Error.DslError,
            path: [:postgres, :references, reference.relationship],
            module: Verifier.get_persisted(dsl, :module),
            message:
              "Found reference configuration for relationship `#{reference.relationship}`, but no such relationship exists",
            location: Spark.Dsl.Transformer.get_section_anno(dsl, [:postgres, :references])

        relationship.type != :belongs_to ->
          raise Spark.Error.DslError,
            path: [:postgres, :references, reference.relationship],
            module: Verifier.get_persisted(dsl, :module),
            message:
              "Found reference configuration for relationship `#{reference.relationship}`, but it is a `#{relationship.type}` relationship. " <>
                "References can only be configured for `belongs_to` relationships, because the foreign key is defined on the table with the `belongs_to` relationship. " <>
                "To configure the behavior of this foreign key, add the reference configuration to the resource with the corresponding `belongs_to` relationship.",
            location: Spark.Dsl.Transformer.get_section_anno(dsl, [:postgres, :references])

        true ->
          :ok
      end
    end)

    :ok
  end
end
