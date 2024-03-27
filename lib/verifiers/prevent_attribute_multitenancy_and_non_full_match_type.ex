defmodule AshPostgres.Verifiers.PreventAttributeMultitenancyAndNonFullMatchType do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    if Verifier.get_option(dsl, [:multitenancy], :strategy) == :attribute do
      dsl
      |> AshPostgres.DataLayer.Info.references()
      |> Enum.filter(&(&1.match_type && &1.match_type != :full))
      |> Enum.each(fn reference ->
        relationship = Ash.Resource.Info.relationship(dsl, reference.relationship)

        if uses_attribute_strategy?(relationship) and
             not targets_primary_key?(relationship) and
             not targets_multitenancy_attribute?(relationship) do
          resource = Verifier.get_persisted(dsl, :module)

          raise Spark.Error.DslError,
            module: resource,
            message: """
            Unsupported match_type.

            The reference #{inspect(resource)}.#{reference.relationship} can't have `match_type: :#{reference.match_type}` because it's referencing another multitenant resource with attribute strategy using a non-primary key index, which requires using `match_type: :full`.
            """,
            path: [:postgres, :references, reference.relationship]
        else
          :ok
        end
      end)
    end

    :ok
  end

  defp uses_attribute_strategy?(relationship) do
    Ash.Resource.Info.multitenancy_strategy(relationship.destination) == :attribute
  end

  defp targets_primary_key?(relationship) do
    Ash.Resource.Info.attribute(
      relationship.destination,
      relationship.destination_attribute
    )
    |> Map.fetch!(:primary_key?)
  end

  defp targets_multitenancy_attribute?(relationship) do
    relationship.destination_attribute ==
      Ash.Resource.Info.multitenancy_attribute(relationship.destination)
  end
end
