# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Verifiers.ValidateCheckConstraints do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)

    dsl
    |> AshPostgres.DataLayer.Info.check_constraints()
    |> Enum.each(fn constraint ->
      constraint.attribute
      |> List.wrap()
      |> Enum.each(fn attribute_name ->
        if is_nil(Ash.Resource.Info.attribute(dsl, attribute_name)) do
          raise Spark.Error.DslError,
            path: [:postgres, :check_constraints, constraint.name],
            module: resource,
            message: """
            Check constraint `#{constraint.name}` references attribute `#{attribute_name}`, but no such attribute exists on resource `#{inspect(resource)}`.

            Available attributes: #{dsl |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name) |> inspect()}
            """,
            location: Spark.Dsl.Transformer.get_section_anno(dsl, [:postgres, :check_constraints])
        end
      end)
    end)

    :ok
  end
end
