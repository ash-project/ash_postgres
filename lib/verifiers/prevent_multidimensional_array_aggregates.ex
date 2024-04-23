defmodule AshPostgres.Verifiers.PreventMultidimensionalArrayAggregates do
  @moduledoc false
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl) do
    resource = Verifier.get_persisted(dsl, :module)

    dsl
    |> Ash.Resource.Info.aggregates()
    |> Stream.filter(&(&1.kind in [:list, :first]))
    |> Stream.filter(& &1.field)
    |> Enum.each(fn aggregate ->
      related = Ash.Resource.Info.related(resource, aggregate.relationship_path)

      related_field =
        if related do
          Ash.Resource.Info.field(related, aggregate.field)
        end

      type =
        if related_field do
          related_field.type
        end

      case type do
        {:array, _} ->
          raise Spark.Error.DslError,
            module: resource,
            path: [:aggregates, aggregate.name],
            message: """
            Aggregate not supported.

            Aggregate #{inspect(resource)}.#{aggregate.name} is not supported, because its type is `#{aggregate.kind}`, and the destination attribute is an array.

            Postgres does not support multidimensional arrays with differing lengths internally. In the future we may be able to remove this restriction
            for the `:first` type aggregate, but likely never for `:list`. In the meantime, you will have to use a custom calculation to get this data.
            """

        _ ->
          :ok
      end
    end)

    :ok
  end
end
