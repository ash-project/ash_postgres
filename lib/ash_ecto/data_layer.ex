defmodule AshEcto.DataLayer do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Ash.DataLayer
      # TODOs: It might be weird that they have to provide their own repo?

      require AshEcto.Schema

      unless opts[:repo] do
        raise "You must configure your own repo"
      end

      unless opts[:repo].__adapter__() == Ecto.Adapters.Postgres do
        raise "Only Ecto.Adapters.Postgres is supported with AshEcto for now"
      end

      @repo opts[:repo]

      # @impl true
      # def update(%resource{} = record, _action, attributes, relationships, _params) do
      #   @repo.transaction(fn ->
      #     changeset =
      #       record
      #       |> Ecto.Changeset.cast(attributes, Map.keys(attributes))
      #       |> AshEcto.DataLayer.cast_assocs(@repo, resource, relationships)

      #     result =
      #       case @repo.update(changeset) do
      #         {:ok, result} -> result
      #         {:error, changeset} -> @repo.rollback(changeset)
      #       end

      #     case changeset do
      #       %{__after_action__: [_ | _] = after_action_hooks} ->
      #         Enum.each(after_action_hooks, fn hook ->
      #           case hook.(changeset, result, @repo) do
      #             :ok -> :ok
      #             {:error, error} -> @repo.rollback(error)
      #             :error -> @repo.rollback(:error)
      #           end
      #         end)

      #         result

      #       _other ->
      #         result
      #     end
      #   end)
      # end

      # @impl true
      # def append_related(record, relationship, resource_identifiers) do
      #   @repo.transaction(fn ->
      #     AshEcto.DataLayer.append_related(@repo, record, relationship, resource_identifiers)
      #   end)
      # end

      # @impl true
      # def delete_related(record, relationship, resource_identifiers) do
      #   @repo.transaction(fn ->
      #     AshEcto.DataLayer.delete_related(@repo, record, relationship, resource_identifiers)
      #   end)
      # end

      # @impl true
      # def replace_related(record, relationship, resource_identifiers) do
      #   @repo.transaction(fn ->
      #     AshEcto.DataLayer.replace_related(@repo, record, relationship, resource_identifiers)
      #   end)
      # end

      # @impl true
      # def delete(record, _action, _params) do
      #   @repo.delete(record)
      # end
    end
  end

  # @doc false
  # def replace_related(
  #       repo,
  #       record,
  #       %{
  #         type: :many_to_many,
  #         through: through,
  #         source_field: source_field,
  #         source_field_on_join_table: source_field_on_join_table,
  #         destination_field_on_join_table: destination_field_on_join_table
  #       },
  #       identifiers
  #     ) do
  #   ids = identifiers |> Enum.map(&Map.get(&1, :id)) |> Enum.reject(&is_nil/1)

  #   source_id = Map.get(record, source_field)

  #   delete_now_unrelated_ids(
  #     repo,
  #     source_id,
  #     through,
  #     source_field_on_join_table,
  #     destination_field_on_join_table,
  #     ids
  #   )

  #   upsert_join_table_rows(
  #     repo,
  #     source_id,
  #     through,
  #     identifiers,
  #     source_field_on_join_table,
  #     destination_field_on_join_table
  #   )

  #   record
  # end

  # def replace_related(
  #       repo,
  #       record,
  #       %{
  #         type: :has_many,
  #         source_field: source_field,
  #         destination: destination,
  #         destination_field: destination_field
  #       },
  #       identifiers
  #     ) do
  #   ids = identifiers |> Enum.map(&Map.get(&1, :id)) |> Enum.reject(&is_nil/1)

  #   field_value = Map.get(record, source_field)

  #   query =
  #     from(row in destination,
  #       where: row.id in ^ids
  #     )

  #   repo.update_all(query, set: [{destination_field, field_value}])

  #   record
  # end

  # def replace_related(
  #       repo,
  #       record,
  #       %{
  #         type: :belongs_to,
  #         source_field: source_field
  #       },
  #       identifier
  #     ) do
  #   value =
  #     case identifier do
  #       %{id: id} -> id
  #       nil -> nil
  #       _ -> raise "what do"
  #     end

  #   record
  #   |> Ecto.Changeset.cast(%{source_field => value}, [source_field])
  #   |> repo.update()
  #   |> case do
  #     {:ok, record} -> record
  #     {:error, error} -> repo.rollback(error)
  #   end
  # end

  # def replace_related(
  #       repo,
  #       record,
  #       %{
  #         type: :has_one,
  #         source_field: source_field,
  #         destination_field: destination_field,
  #         destination: destination
  #       },
  #       identifier
  #     ) do
  #   value =
  #     case identifier do
  #       %{id: id} -> id
  #       nil -> nil
  #       _ -> raise "what"
  #     end

  #   query =
  #     from(row in destination,
  #       where: field(row, ^destination_field) == ^Map.get(record, source_field)
  #     )

  #   repo.update_all(query, set: [{destination_field, value}])

  #   record
  # end

  # @doc false
  # def append_related(repo, record, %{type: :many_to_many} = relationship, identifiers) do
  #   source_id = Map.get(record, relationship.source_field)

  #   upsert_join_table_rows(
  #     repo,
  #     source_id,
  #     relationship.through,
  #     identifiers,
  #     relationship.source_field_on_join_table,
  #     relationship.destination_field_on_join_table
  #   )

  #   record
  # end

  # def append_related(
  #       repo,
  #       record,
  #       %{type: :has_many, destination: destination, destination_field: destination_field},
  #       identifiers
  #     ) do
  #   ids =
  #     identifiers
  #     |> Enum.map(&Map.get(&1, :id))
  #     |> Enum.reject(&is_nil/1)

  #   query =
  #     from(related in destination,
  #       where: related.id in ^ids,
  #       where: field(related, ^destination_field) != ^record.id
  #     )

  #   repo.update_all(query, set: [{destination_field, record.id}])
  # end

  # @doc false
  # def delete_related(repo, record, %{type: :many_to_many} = relationship, identifiers) do
  #   source_id = Map.get(record, relationship.source_field)

  #   ids =
  #     identifiers
  #     |> Enum.map(&Map.get(&1, :id))
  #     |> Enum.reject(&is_nil/1)

  #   delete_related_ids(
  #     repo,
  #     source_id,
  #     relationship.through,
  #     relationship.source_field_on_join_table,
  #     relationship.destination_field_on_join_table,
  #     ids
  #   )

  #   record
  # end

  # def delete_related(
  #       repo,
  #       record,
  #       %{type: :has_many, destination: destination, destination_field: destination_field},
  #       identifiers
  #     ) do
  #   ids =
  #     identifiers
  #     |> Enum.map(&Map.get(&1, :id))
  #     |> Enum.reject(&is_nil/1)

  #   query =
  #     from(related in destination,
  #       where: related.id in ^ids,
  #       where: field(related, ^destination_field) != ^record.id
  #     )

  #   # TODO: Validate the a delete_related action doesn't exist for has_many relationships
  #   # where the destination field is not nullable. That will only ever error.

  #   repo.update_all(query, set: [{destination_field, record.id}])
  # end

  # defp delete_related_ids(
  #        repo,
  #        source_id,
  #        through,
  #        source_field_on_join_table,
  #        destination_field_on_join_table,
  #        ids
  #      ) do
  #   query =
  #     from(join_row in through,
  #       where: field(join_row, ^destination_field_on_join_table) in ^ids,
  #       where: field(join_row, ^source_field_on_join_table) == ^source_id
  #     )

  #   repo.delete_all(query)
  # end

  # def add_through_schema_fields(repo, resource, includes) when is_list(includes) do
  #   Enum.flat_map(includes, fn {rel, further} ->
  #     case Ash.relationship(resource, rel) do
  #       %{type: :many_to_many, destination: destination} = relationship ->
  #         [
  #           {rel, &fetch_and_add_through_row(&1, repo, relationship)},
  #           {rel, add_through_schema_fields(repo, destination, further)}
  #         ]

  #       %{destination: destination} ->
  #         [
  #           {rel, add_through_schema_fields(repo, destination, further)}
  #         ]
  #     end
  #   end)
  # end

  # def add_through_schema_fields(_repo, _resource, includes), do: includes

  # defp fetch_and_add_through_row(source_ids, repo, relationship) do
  #   query =
  #     from(join_row in relationship.through,
  #       where:
  #         type(field(join_row, ^relationship.source_field_on_join_table), :binary_id) in ^source_ids,
  #       join: destination_row in ^relationship.destination,
  #       on:
  #         type(field(join_row, ^relationship.destination_field_on_join_table), :binary_id) ==
  #           field(destination_row, ^relationship.destination_field)
  #     )

  #   query
  #   |> add_select(relationship)
  #   |> repo.all()
  #   |> Enum.map(fn {destination_row, join_row} ->
  #     {Map.get(join_row, relationship.source_field_on_join_table),
  #      Map.put(destination_row, :__join_row__, join_row)}
  #   end)
  # end

  # defp add_select(query, relationship) do
  #   case relationship.through do
  #     string when is_bitstring(string) ->
  #       from([join_row, destination_row] in query,
  #         select:
  #           {destination_row,
  #            %{
  #              ^relationship.source_field_on_join_table =>
  #                type(field(join_row, ^relationship.source_field_on_join_table), :binary_id),
  #              ^relationship.destination_field_on_join_table =>
  #                type(field(join_row, ^relationship.destination_field_on_join_table), :binary_id)
  #            }}
  #       )

  #     module when is_atom(module) ->
  #       from([join_row, destination_row] in query,
  #         select: {destination_row, join_row}
  #       )
  #   end
  # end
end
