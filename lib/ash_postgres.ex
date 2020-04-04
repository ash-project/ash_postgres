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
  def can?(:query_async), do: true
  def can?(:transact), do: true
  def can?(:composite_primary_key), do: true
  def can?({:filter, :in}), do: true
  def can?({:filter, :not_in}), do: true
  def can?({:filter, :not_eq}), do: true
  def can?({:filter, :eq}), do: true
  def can?({:filter, :and}), do: true
  def can?({:filter, :or}), do: true
  def can?({:filter, :not}), do: true
  def can?({:filter_related, _}), do: true
  def can?(_), do: false

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
    changeset =
      Map.update!(changeset, :action, fn
        :create -> :insert
        action -> action
      end)

    repo(resource).insert(changeset)
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def update(resource, changeset) do
    repo(resource).update(changeset)
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def sort(query, sort, _resource) do
    {:ok,
     from(row in query,
       order_by: ^sort
     )}
  end

  @impl true
  # TODO: I have learned from experience that no single approach here
  # will be a one-size-fits-all. We need to either use complexity metrics,
  # hints from the interface, or some other heuristic to do our best to
  # make queries perform well. For now, I'm just choosing the most naive approach
  # possible: left join to relationships that appear in `or` conditions, inner
  # join to conditions in the mainline query.

  def filter(query, filter, resource) do
    new_query =
      query
      |> Map.put(:bindings, %{})
      |> join_all_relationships(filter)
      |> add_filter_expression(filter)

    {:ok, new_query}
  end

  defp join_all_relationships(query, filter, path \\ [])

  defp join_all_relationships(query, %{relationships: relationships}, _path)
       when relationships == %{} do
    query
  end

  defp join_all_relationships(query, filter, path) do
    query =
      Map.put_new(query, :__ash_bindings__, %{current: Enum.count(query.joins) + 1, bindings: %{}})

    Enum.reduce(filter.relationships, query, fn {name, relationship_filter}, query ->
      # TODO: This can be smarter. If the same relationship exists in all `ors`,
      # we can inner join it, (unless the filter is only for fields being null)
      join_type =
        if Enum.empty?(filter.ors) && filter.not == nil do
          :inner
        else
          :left
        end

      current_path = [Ash.relationship(filter.resource, name) | path]

      joined_query = join_relationship(query, current_path, join_type)

      join_all_relationships(joined_query, relationship_filter, current_path)
    end)
  end

  defp join_relationship(query, path, join_type) do
    path_names = Enum.map(path, & &1.name)

    case Map.get(query.__ash_bindings__.bindings, path_names) do
      %{type: existing_join_type} when join_type != existing_join_type ->
        raise "unreachable?"

      nil ->
        do_join_relationship(query, path, join_type)

      _ ->
        query
    end
  end

  defp do_join_relationship(query, [%{type: :many_to_many} = relationship], :inner) do
    new_query =
      from(row in query,
        join: through in ^relationship.through,
        on:
          field(row, ^relationship.source_field) ==
            field(through, ^relationship.source_field_on_join_table),
        join: destination in ^relationship.destination,
        on:
          field(destination, ^relationship.destination_field) ==
            field(through, ^relationship.destination_field_on_join_table)
      )

    join_path = [String.to_existing_atom(to_string(relationship.name) <> "_join_assoc")]
    full_path = [relationship.name]

    new_query
    |> add_binding(join_path, :inner)
    |> add_binding(full_path, :inner)
  end

  defp do_join_relationship(query, [relationship], :inner) do
    new_query =
      from(row in query,
        join: destination in ^relationship.destination,
        on: field(row, ^relationship.source_field) == field(row, ^relationship.destination_field)
      )

    add_binding(new_query, [relationship.name], :inner)
  end

  defp add_filter_expression(query, filter) do
    {params, not_expr} =
      case filter.not do
        nil ->
          {[], nil}

        not_filter ->
          filter_to_expr(not_filter)
      end

    {params, expr} = filter_to_expr(filter, query.__ash_bindings__.bindings, params)

    expr = join_exprs(not_expr, expr, :and)

    {params, expr} =
      Enum.reduce(filter.ors, {params, expr}, fn or_filter, {params, existing_expr} ->
        {params, expr} = filter_to_expr(or_filter, params)

        {params, join_exprs(existing_expr, expr, :or)}
      end)

    if expr do
      query
    else
      boolean_expr = %Ecto.Query.BooleanExpr{
        expr: expr,
        op: :and,
        params: params
      }

      %{query | wheres: [boolean_expr | query.wheres]}
    end
  end

  defp join_exprs(nil, nil, _op), do: nil
  defp join_exprs(expr, nil, _op), do: expr
  defp join_exprs(nil, expr, _op), do: expr
  defp join_exprs(expr, expr, op), do: {op, expr, expr}

  defp filter_to_expr(filter, bindings, current_binding \\ 0, params \\ [], path \\ []) do
    param_count = Enum.count(params)

    {params, existing_expr, _param_count} =
      Enum.reduce(filter.attributes, {params, nil, param_count}, fn {attribute, filter},
                                                                    {params, existing_expr,
                                                                     param_count} ->
        case filter_value_to_expr(attribute, filter, current_binding) do
          {param, expr} ->
            {params ++ [param], join_exprs(existing_expr, expr, :and), param_count + 1}

          expr ->
            {params, join_exprs(existing_expr, expr, :and), param_count}
        end
      end)

    Enum.reduce(filter.relationships, {params, existing_expr}, fn {relationship,
                                                                   relationship_filter},
                                                                  {params, existing_expr} ->
      full_path = path ++ [relationship]

      binding = Map.get(bindings, full_path) || raise "unbound relationship referenced!"

      {params, expr} = filter_to_expr(relationship_filter, bindings, binding, params, full_path)

      {params, join_exprs(expr, existing_expr)}
    end)
  end

  defp add_binding(query, path, type) do
    current = query.__ash_bindings__.current
    bindings = query.__ash_bindings__.bindings

    new_ash_bindings = %{
      query.__ash_bindings__
      | bindings: do_add_binding(bindings, path, current, type),
        current: current + 1
    }

    %{query | __ash_bindings__: new_ash_bindings}
  end

  defp do_add_binding(bindings, path, current, type) do
    Map.put(bindings, path, %{binding: current, type: type})
  end

  # defp join_all_relationships(query, filter, kind \\ :inner) do
  #   case filter.ors do
  #     [] ->
  #       Enum.reduce(filter.relationships, query, fn {relationship_name, filter}, query ->
  #         relationship = Ash.relationship(filter.resource, relationship_name)
  #         join_relationship(query, relationship, filter, kind)
  #       end)

  #     ors ->
  #       Enum.reduce([filter | ors], query, fn filter, query ->
  #         join_all_relationships(query, Map.put(filter, :ors, []), :left)
  #       end)
  #   end
  # end

  # defp join_relationships(_query, _relationship, _filter, :left), do: raise "unimplemented"
  # defp join_relationship(query, %{type: :many_to_many} = relationship, filter, _type) do
  #   filtered_destination = filter(Ecto.Queryable.to_query(relationship.destination), filter, relationship.destination)

  #   from row in query,
  #     left_join: through in ^relationship.through,
  #     on: field(row, ^relationship.source_field) == field(through, ^relationship.source_field_on_join_table),
  #     left_join: destination in ^filtered_destination,
  #     on: field(destination, ^relationship.destination_field) == field(through, ^relationship.destination_field_on_join_table)
  # end

  # defp join_relationship(query, relationship, filter, join_kind) do
  #   filtered_destination = filter(Ecto.Queryable.to_query(relationship.destination), filter, relationship.destination)

  #   from row in query,
  #     join: destination in ^filtered_destination,
  #     on: field(row, ^relationship.source_field) == field(destination, ^relationship.destination_field)
  #   query
  # end

  defp do_filter(query, key, :equals, value) do
    from(row in query,
      where: field(row, ^key) == ^value
    )
  end

  defp do_filter(query, key, :in, value) do
    from(row in query,
      where: field(row, ^key) == ^value
    )
  end

  defp do_filter(_, key, type, value) do
    {:error, "Invalid filter #{key} #{type} #{inspect(value)}"}
  end

  @impl true
  def can_query_async?(resource) do
    repo(resource).in_transaction?()
  end

  @impl true
  def transaction(resource, func) do
    repo(resource).transaction(func)
  end
end
