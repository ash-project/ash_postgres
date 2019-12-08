defmodule AshPostgres do
  @using_opts_schema Ashton.schema(
                       opts: [
                         repo: :atom
                       ],
                       required: [:repo],
                       describe: [
                         repo:
                           "The repo that will be used to fetch your data. See the `Ecto.Repo` documentation for more"
                       ],
                       constraints: [
                         repo:
                           {&AshPostgres.postgres_repo?/1, "must be using the postgres adapter"}
                       ]
                     )

  @moduledoc """
  A postgres data layer that levereges Ecto's postgres tools.

  To use it, add `use AshPostgres, repo: MyRepo` to your resource, after `use Ash.Resource`

  #{Ashton.document(@using_opts_schema)}
  """
  @behaviour Ash.DataLayer

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      opts = AshPostgres.validate_using_opts(__MODULE__, opts)

      @data_layer AshPostgres
      @repo opts[:repo]

      def repo() do
        @repo
      end
    end
  end

  def validate_using_opts(mod, opts) do
    case Ashton.validate(opts, @using_opts_schema) do
      {:ok, opts} ->
        opts

      {:error, [{key, message} | _]} ->
        raise Ash.Error.ResourceDslError,
          resource: mod,
          using: __MODULE__,
          option: key,
          message: message
    end
  end

  def postgres_repo?(repo) do
    repo.__adapter__() == Ecto.Adapters.Postgres
  end

  def repo(resource) do
    resource.repo()
  end

  import Ecto.Query, only: [from: 2]

  @impl true
  def can?(:query_async), do: false
  def can?(:transact), do: false

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
  def create(resource, changeset) do
    repo = repo(resource)

    repo.transaction(fn ->
      # changeset = cast_assocs(changeset, repo, resource, )

      result =
        try do
          changeset
          |> repo.insert()
          |> case do
            {:ok, result} -> result
            {:error, changeset} -> repo.rollback(changeset)
          end
        rescue
          e ->
            repo.rollback(e)
        end

      case changeset do
        %{__after_action__: [_ | _] = after_action_hooks} ->
          Enum.each(after_action_hooks, fn hook ->
            case hook.(changeset, result, repo) do
              :ok -> :ok
              {:error, error} -> repo.rollback(error)
              :error -> repo.rollback(:error)
            end
          end)

          result

        _ ->
          result
      end
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

  # def cast_assocs(changeset, repo, resource, relationships) do
  #   Enum.reduce(relationships, changeset, fn {relationship, value}, changeset ->
  #     case Ash.relationship(resource, relationship) do
  #       %{type: :belongs_to, source_field: source_field} ->
  #         belongs_to_assoc_update(changeset, source_field, value)

  #       %{type: :has_one} = rel ->
  #         has_one_assoc_update(changeset, repo, rel, value)

  #       %{type: :has_many} = rel ->
  #         has_many_assoc_update(changeset, rel, value)

  #       %{type: :many_to_many} = rel ->
  #         many_to_many_assoc_update(changeset, rel, value, repo)

  #       _ ->
  #         changeset
  #     end
  #   end)
  # end

  # defp has_one_assoc_update(
  #        changeset,
  #        repo,
  #        %{
  #          destination: destination,
  #          destination_field: destination_field,
  #          source_field: source_field
  #        },
  #        identifier
  #      ) do
  #   Ecto.Changeset.prepare_changes(changeset, fn changeset ->
  #     value =
  #       case identifier do
  #         %{id: id} -> id
  #         nil -> nil
  #         _ -> raise "what"
  #       end

  #     query =
  #       from(row in destination,
  #         where:
  #           field(row, ^destination_field) == ^Ecto.Changeset.get_field(changeset, source_field)
  #       )

  #     repo.update_all(query, set: [{destination_field, value}])

  #     changeset
  #   end)
  # end

  # defp belongs_to_assoc_update(changeset, source_field, %{id: id}) do
  #   Ecto.Changeset.cast(changeset, %{source_field => id}, [source_field])
  # end

  # defp belongs_to_assoc_update(changeset, source_field, nil) do
  #   Ecto.Changeset.cast(changeset, %{source_field => nil}, [source_field])
  # end

  # defp has_many_assoc_update(
  #        changeset,
  #        %{
  #          destination: destination,
  #          destination_field: destination_field,
  #          source_field: source_field
  #        },
  #        values
  #      ) do
  #   ids = values |> Enum.map(&Map.get(&1, :id)) |> Enum.reject(&is_nil/1)

  #   add_after_action_hook(changeset, fn _changeset, result, repo ->
  #     field_value = Map.get(result, source_field)

  #     query =
  #       from(row in destination,
  #         where: row.id in ^ids
  #       )

  #     repo.update_all(query, set: [{destination_field, field_value}])

  #     :ok
  #   end)
  # end

  # defp many_to_many_assoc_update(
  #        changeset,
  #        %{
  #          through: through,
  #          source_field: source_field,
  #          source_field_on_join_table: source_field_on_join_table,
  #          destination_field_on_join_table: destination_field_on_join_table,
  #          join_table_fields: join_table_fields
  #        },
  #        values,
  #        repo
  #      ) do
  #   ids = values |> Enum.map(&Map.get(&1, :id)) |> Enum.reject(&is_nil/1)

  #   source_id =
  #     Ecto.Changeset.get_field(
  #       changeset,
  #       source_field
  #     )

  #   changeset
  #   |> Ecto.Changeset.prepare_changes(fn changeset ->
  #     delete_now_unrelated_ids(
  #       repo,
  #       source_id,
  #       through,
  #       source_field_on_join_table,
  #       destination_field_on_join_table,
  #       ids
  #     )

  #     changeset
  #   end)
  #   |> add_after_action_hook(fn _changeset, _result, repo ->
  #     case upsert_join_table_rows(
  #            repo,
  #            source_id,
  #            through,
  #            values,
  #            source_field_on_join_table,
  #            destination_field_on_join_table,
  #            join_table_fields
  #          ) do
  #       :ok ->
  #         :ok
  #     end
  #   end)
  # end

  # defp delete_now_unrelated_ids(
  #        repo,
  #        source_id,
  #        through,
  #        source_field_on_join_table,
  #        destination_field_on_join_table,
  #        ids
  #      ) do
  #   query =
  #     from(join_row in through,
  #       where: field(join_row, ^destination_field_on_join_table) not in ^ids,
  #       where: field(join_row, ^source_field_on_join_table) == ^source_id
  #     )

  #   repo.delete_all(query)
  # end

  # defp upsert_join_table_rows(
  #        repo,
  #        source_id,
  #        through,
  #        values,
  #        source_field_on_join_table,
  #        destination_field_on_join_table,
  #        join_table_fields
  #      ) do
  #   values
  #   |> Enum.map(fn fields ->
  #     update_fields = Map.delete(fields, :id)

  #     cond do
  #       is_nil(Map.get(fields, :id)) ->
  #         {:error, "No destination id specified"}

  #       is_bitstring(through) ->
  #         {:error, "Cannot update the fields of a join table only specified as a table name"}

  #       Map.keys(update_fields) -- join_table_fields != [] ->
  #         {:error, "no such fields to update"}

  #       true ->
  #         attributes =
  #           update_fields
  #           |> Map.put(source_field_on_join_table, source_id)
  #           |> Map.put(destination_field_on_join_table, Map.get(fields, :id))

  #         changeset =
  #           through
  #           |> struct()
  #           |> Ecto.Changeset.cast(
  #             attributes,
  #             join_table_fields ++ [source_field_on_join_table, destination_field_on_join_table]
  #           )

  #         repo.insert(changeset,
  #           on_conflict: :replace_all_except_primary_key,
  #           conflict_target: [source_field_on_join_table, destination_field_on_join_table]
  #         )
  #     end
  #   end)
  #   |> Enum.filter(fn result -> match?({:error, _}, result) end)
  #   |> case do
  #     [] -> :ok
  #     errors -> {:error, errors}
  #   end
  # end

  # defp add_after_action_hook(changeset, hook) do
  #   changeset
  #   |> Map.put_new(:__after_action__, [])
  #   |> Map.update!(:__after_action__, fn list -> [hook | list] end)
  # end

  # Copied from an older file, to be added as more functionality is added back in

  # @impl true
  # def update(%resource{} = record, _action, attributes, relationships, _params) do
  #   @repo.transaction(fn ->
  #     changeset =
  #       record
  #       |> Ecto.Changeset.cast(attributes, Map.keys(attributes))
  #       |> AshPostgres.DataLayer.cast_assocs(@repo, resource, relationships)

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
  #     AshPostgres.DataLayer.append_related(@repo, record, relationship, resource_identifiers)
  #   end)
  # end

  # @impl true
  # def delete_related(record, relationship, resource_identifiers) do
  #   @repo.transaction(fn ->
  #     AshPostgres.DataLayer.delete_related(@repo, record, relationship, resource_identifiers)
  #   end)
  # end

  # @impl true
  # def replace_related(record, relationship, resource_identifiers) do
  #   @repo.transaction(fn ->
  #     AshPostgres.DataLayer.replace_related(@repo, record, relationship, resource_identifiers)
  #   end)
  # end

  # @impl true
  # def delete(record, _action, _params) do
  #   @repo.delete(record)
  # end

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
