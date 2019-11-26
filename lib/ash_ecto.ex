defmodule AshEcto do
  @behaviour Ash.DataLayer

  defmacro __using__(opts) do
    quote bind_quoted: [repo: opts[:repo]] do
      @data_layer AshEcto
      @mix_ins AshEcto
      @repo repo

      require AshEcto.Schema

      unless repo do
        raise "You must pass the `repo` option to `use AshEcto` for #{__MODULE__}"
      end

      unless repo.__adapter__() == Ecto.Adapters.Postgres do
        raise "Only Ecto.Adapters.Postgres is supported with AshEcto for now"
      end

      def repo() do
        @repo
      end
    end
  end

  def repo(resource) do
    resource.repo()
  end

  import Ecto.Query, only: [from: 2]

  @impl true
  def limit(query, limit, _resource) do
    {:ok, from(row in query, limit: ^limit)}
  end

  @impl true
  def offset(query, offset, _resource) do
    {:ok, from(row in query, offset: ^offset)}
  end

  @impl true
  def run_query(query, resource) do
    {:ok, repo(resource).all(query)}
  end

  @impl true
  def resource_to_query(resource), do: Ecto.Queryable.to_query(resource)

  @impl true
  def filter(_query, :from_related, {_records, %{cardinality: :many_to_many}}, _resource) do
    raise "Not implemented yet!"
  end

  def filter(query, :from_related, {records, relationship}, _resource) do
    ids = Enum.map(records, &Map.get(&1, relationship.source_field))

    {:ok,
     from(row in query,
       where: field(row, ^relationship.destination_field) in ^ids
     )}
  end

  # TODO This is a really dumb implementation of this.
  def filter(query, key, value, _central_resource) do
    query =
      from(row in query,
        where: field(row, ^key) == ^value
      )

    {:ok, query}
  end

  @impl true
  def can_query_async?(resource) do
    repo(resource).in_transaction?()
  end

  def before_compile_hook(_env) do
    quote do
      require AshEcto.Schema

      AshEcto.Schema.define_schema(@name)
    end
  end
end
