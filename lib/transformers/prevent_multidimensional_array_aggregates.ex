defmodule AshPostgres.Transformers.PreventMultidimensionalArrayAggregates do
  @moduledoc "Prevents at compile time certain aggregates that are unsupported by AshPostgres"
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after_compile?, do: true

  def transform(dsl) do
    resource = Transformer.get_persisted(dsl, :module)

    dsl
    |> Ash.Resource.Info.aggregates()
    |> Stream.filter(&(&1.kind in [:list, :first]))
    |> Stream.filter(& &1.field)
    |> Enum.each(fn aggregate ->
      related = Ash.Resource.Info.related(resource, aggregate.relationship_path)
      type = Ash.Resource.Info.field(related, aggregate.field).type

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

    repo = Transformer.get_option(dsl, [:postgres], :repo)

    cond do
      match?({:error, _}, Code.ensure_compiled(repo)) ->
        {:error, "Could not find repo module #{repo}"}

      repo.__adapter__() != Ecto.Adapters.Postgres ->
        {:error, "Expected a repo using the postgres adapter `Ecto.Adapters.Postgres`"}

      true ->
        {:ok, dsl}
    end
  end
end
