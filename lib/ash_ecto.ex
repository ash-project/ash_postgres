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
  def create(_resource, _attributes, relationships) when relationships != %{} do
    {:error, "Ash ecto does not currently support creating with relationships"}
  end

  def create(resource, attributes, _relationships) do
    # TODO: validation should happen before this step
    repo = repo(resource)

    repo.transaction(fn ->
      changeset =
        resource
        |> struct()
        |> Ecto.Changeset.cast(attributes, Map.keys(attributes))

      # |> AshEcto.DataLayer.cast_assocs(repo, resource, relationships)

      # result =
      case repo.insert(changeset) do
        {:ok, result} -> result
        {:error, changeset} -> repo.rollback(changeset)
      end

      # case changeset do
      #   %{__after_action__: [_ | _] = after_action_hooks} ->
      #     Enum.each(after_action_hooks, fn hook ->
      #       case hook.(changeset, result, @repo) do
      #         :ok -> :ok
      #         {:error, error} -> @repo.rollback(error)
      #         :error -> @repo.rollback(:error)
      #       end
      #     end)

      #     result

      #   _ ->
      #     result
      # end
    end)
  end

  @impl true
  def sort(query, sort, _resource) do
    {:ok,
     from(row in query,
       order_by: ^sort
     )}
  end

  @impl true
  def filter(query, filter, resource) do
    Enum.reduce(filter, {:ok, query}, fn
      _, {:error, error} ->
        {:error, error}

      {key, value}, {:ok, query} ->
        do_filter(query, key, value, resource)
    end)
  end

  defp do_filter(
         query,
         :from_related,
         {records, %{cardinality: :many_to_many} = relationship},
         _resource
       ) do
    ids = Enum.map(records, &Map.get(&1, relationship.source_field))

    {:ok,
     from(row in query,
       join: join_row in ^relationship.through,
       on:
         field(join_row, ^relationship.destination_field_on_join_table) ==
           field(row, ^relationship.destination_field),
       where: field(join_row, ^relationship.source_field_on_join_table) in ^ids,
       select_merge: %{__related_id__: field(join_row, ^relationship.source_field_on_join_table)}
     )}
  end

  defp do_filter(query, :from_related, {records, relationship}, _resource) do
    ids = Enum.map(records, &Map.get(&1, relationship.source_field))

    {:ok,
     from(row in query,
       where: field(row, ^relationship.destination_field) in ^ids
     )}
  end

  # TODO This is a really dumb implementation of this.
  defp do_filter(query, key, value, resource) do
    cond do
      attr = Ash.attribute(resource, key) ->
        filter_attribute(query, attr, value, resource)

      rel = Ash.relationship(resource, key) ->
        filter_relationship(query, rel, value, resource)

      true ->
        {:error, "No such filter"}
    end
  end

  defp filter_attribute(query, attribute, value, _resource) do
    query =
      from(row in query,
        where: field(row, ^attribute.name) == ^value
      )

    {:ok, query}
  end

  # Only supports a single id for now
  defp filter_relationship(query, %{name: name}, id, _resource) do
    query =
      from(row in query,
        join: related in assoc(row, ^name),
        where: related.id == ^id
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
