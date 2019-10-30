defmodule AshEcto.DataLayer do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Ash.DataLayer
      # TODOs: It might be weird that they have to provide their own repo?

      require AshEcto.Schema

      unless opts[:repo] do
        raise "You must configure your own repo"
      end

      unless opts[:repo].__adapter__() == Ecto.Adapters.Postgres do
        raise "#{}Only Ecto.Adapters.Postgres is supported with AshEcto for now"
      end

      @repo opts[:repo]

      import Ecto.Query, only: [from: 2]

      @impl true
      def relationship_query(record, %{name: name}) do
        {:ok, Ecto.assoc(record, name)}
      end

      @impl true
      def get_one(query, _) do
        {:ok, @repo.one(query)}
      end

      @impl true
      def get_many(query, _) do
        {:ok, @repo.all(query)}
      end

      @impl true
      def limit(query, limit, _) do
        {:ok, from(row in query, limit: ^limit)}
      end

      @impl true
      def offset(query, offset, _) do
        {:ok, from(row in query, offset: ^offset)}
      end

      @impl true
      def resource_to_query(resource) do
        {:ok, Ecto.Query.from(resource)}
      end

      @impl true
      def side_load(records, side_load_keyword, _resource) do
        {:ok, @repo.preload(records, side_load_keyword)}
      end

      @impl true
      def filter(query, key, value, _central_resource) do
        query =
          from(row in query,
            where: field(row, ^key) == ^value
          )

        {:ok, query}
      end
    end
  end
end
