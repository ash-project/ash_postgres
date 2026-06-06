# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Verifiers.ValidateCollations do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  # Ash storage types that map to collatable (text-based) PostgreSQL columns.
  @collatable_storage_types [:string, :ci_string, :citext, :text]

  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)

    dsl
    |> AshPostgres.DataLayer.Info.collations()
    |> Enum.each(fn collation ->
      attribute = Ash.Resource.Info.attribute(dsl, collation.attribute)

      cond do
        is_nil(attribute) ->
          raise Spark.Error.DslError,
            path: [:postgres, :collations, collation.attribute],
            module: resource,
            message: """
            Collation `#{collation.collation}` references attribute `#{collation.attribute}`, but no such attribute exists on resource `#{inspect(resource)}`.

            Available attributes: #{dsl |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name) |> inspect()}
            """,
            location: Spark.Dsl.Transformer.get_section_anno(dsl, [:postgres, :collations])

        not collatable?(attribute) ->
          raise Spark.Error.DslError,
            path: [:postgres, :collations, collation.attribute],
            module: resource,
            message: """
            Collation `#{collation.collation}` is configured for attribute `#{collation.attribute}` of type `#{inspect(attribute.type)}`, but collations can only be applied to string-based (text) columns.
            """,
            location: Spark.Dsl.Transformer.get_section_anno(dsl, [:postgres, :collations])

        true ->
          :ok
      end
    end)

    :ok
  end

  defp collatable?(attribute) do
    storage_type =
      try do
        Ash.Type.storage_type(attribute.type, attribute.constraints || [])
      rescue
        _ -> nil
      end

    storage_type in @collatable_storage_types
  end
end
