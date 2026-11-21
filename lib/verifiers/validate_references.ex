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

    validate_polymorphic_references(dsl)

    :ok
  end

  defp validate_polymorphic_references(dsl) do
    dsl
    |> Ash.Resource.Info.relationships()
    |> Enum.each(fn relationship ->
      with %{data_layer: %{references: references}} <- relationship.context,
           true <- relationship.type in [:has_many, :has_one],
           AshPostgres.DataLayer <- Ash.DataLayer.data_layer(relationship.destination),
           true <- AshPostgres.DataLayer.Info.polymorphic?(relationship.destination) do
        validate_polymorphic_reference(dsl, relationship, references)
      end
    end)
  end

  defp validate_polymorphic_reference(dsl, relationship, references) when is_map(references) do
    schema = Keyword.take(AshPostgres.Reference.schema(), [:on_delete, :on_update, :name])
    unknown_options = Map.keys(references) -- Keyword.keys(schema)

    if unknown_options != [] do
      polymorphic_reference_error!(
        dsl,
        relationship,
        "Unknown reference options: #{inspect(unknown_options)}"
      )
    end

    case Spark.Options.validate(Map.to_list(references), schema) do
      {:ok, options} ->
        for {option, legacy} <- [
              on_delete: :polymorphic_on_delete,
              on_update: :polymorphic_on_update
            ],
            Keyword.has_key?(options, option),
            not is_nil(Verifier.get_option(dsl, [:postgres, :references], legacy)) do
          polymorphic_reference_error!(
            dsl,
            relationship,
            "Cannot configure both relationship_context.data_layer.references.#{option} " <>
              "and postgres.references.#{legacy}. Remove the legacy #{legacy} setting."
          )
        end

      {:error, error} ->
        polymorphic_reference_error!(dsl, relationship, Exception.message(error))
    end
  end

  defp validate_polymorphic_reference(dsl, relationship, references) do
    polymorphic_reference_error!(
      dsl,
      relationship,
      "Expected references to be a map, got: #{inspect(references)}"
    )
  end

  defp polymorphic_reference_error!(dsl, relationship, message) do
    raise Spark.Error.DslError,
      module: Verifier.get_persisted(dsl, :module),
      path: [:relationships, relationship.name, :relationship_context, :data_layer, :references],
      message: message,
      location:
        Spark.Dsl.Entity.property_anno(relationship, :relationship_context) ||
          Spark.Dsl.Entity.anno(relationship)
  end
end
