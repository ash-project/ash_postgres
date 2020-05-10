defmodule AshPostgres do
  @using_opts_schema Ashton.schema(
                       opts: [
                         repo: :atom,
                         table: :string
                       ],
                       required: [:repo],
                       describe: [
                         repo:
                           "The repo that will be used to fetch your data. See the `Ecto.Repo` documentation for more",
                         table: "The name of the database table backing the resource"
                       ],
                       constraints: [
                         repo:
                           {&AshPostgres.postgres_repo?/1, "must be using the postgres adapter"}
                       ]
                     )

  alias Ash.Filter.{And, Eq, In, NotEq, NotIn, Or}

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
      @table opts[:table]

      def repo() do
        @repo
      end

      def postgres_table() do
        @table || @name
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
  def limit(query, nil, _), do: {:ok, query}

  def limit(query, limit, _resource) do
    {:ok, from(row in query, limit: ^limit)}
  end

  @impl true
  def offset(query, nil, _), do: query

  def offset(query, offset, _resource) do
    {:ok, from(row in query, offset: ^offset)}
  end

  @impl true
  def run_query(%{__impossible__: true}, _) do
    {:ok, []}
  end

  @impl true
  def run_query(query, resource) do
    {:ok, repo(resource).all(query)}
  end

  @impl true
  def resource_to_query(resource),
    do: Ecto.Queryable.to_query({resource.postgres_table(), resource})

  @impl true
  def create(resource, changeset) do
    changeset =
      Map.update!(changeset, :action, fn
        :create -> :insert
        action -> action
      end)

    changeset =
      Map.update!(changeset, :data, fn data ->
        Map.update!(data, :__meta__, &Map.put(&1, :source, resource.postgres_table()))
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
  def destroy(%resource{} = record) do
    repo(resource).delete(record)
  rescue
    e ->
      {:error, e}
  end

  @impl true
  def sort(query, sort, _resource) do
    {:ok,
     from(row in query,
       order_by: ^sanitize_sort(sort)
     )}
  end

  defp sanitize_sort(sort) do
    sort
    |> List.wrap()
    |> Enum.map(fn
      {sort, order} -> {order, sort}
      sort -> sort
    end)
  end

  # TODO: I have learned from experience that no single approach here
  # will be a one-size-fits-all. We need to either use complexity metrics,
  # hints from the interface, or some other heuristic to do our best to
  # make queries perform well. For now, I'm just choosing the most naive approach
  # possible: left join to relationships that appear in `or` conditions, inner
  # join to conditions that are constant the query (dont do this yet, but it will be a good optimization)
  # Realistically, in my experience, joins don't actually scale very well, especially
  # when calculated attributes are added.

  @impl true
  def filter(query, filter, _resource) do
    new_query =
      query
      |> Map.put(:bindings, %{})
      |> join_all_relationships(filter)
      |> add_filter_expression(filter)

    impossible_query =
      if filter.impossible? do
        Map.put(new_query, :__impossible__, true)
      else
        new_query
      end

    {:ok, impossible_query}
  end

  defp join_all_relationships(query, filter, path \\ []) do
    query =
      Map.put_new(query, :__ash_bindings__, %{current: Enum.count(query.joins) + 1, bindings: %{}})

    Enum.reduce(filter.relationships, query, fn {name, relationship_filter}, query ->
      # TODO: This can be smarter. If the same relationship exists in all `ors`,
      # we can inner join it, (unless the filter is only for fields being null)
      join_type = :left

      relationship = Ash.relationship(filter.resource, name)

      current_path = [relationship | path]

      joined_query = join_relationship(query, current_path, join_type)

      joined_query_with_distinct =
        if relationship.cardinality == :many and join_type == :left && !joined_query.distinct do
          from(row in joined_query,
            distinct: ^Ash.primary_key(filter.resource)
          )
        else
          joined_query
        end

      join_all_relationships(joined_query_with_distinct, relationship_filter, current_path)
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
    relationship_through = maybe_get_resource_query(relationship.through)
    relationship_destination = maybe_get_resource_query(relationship.destination)

    new_query =
      from(row in query,
        join: through in ^relationship_through,
        on:
          field(row, ^relationship.source_field) ==
            field(through, ^relationship.source_field_on_join_table),
        join: destination in ^relationship_destination,
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
    relationship_destination = maybe_get_resource_query(relationship.destination)

    new_query =
      from(row in query,
        join: destination in ^relationship_destination,
        on: field(row, ^relationship.source_field) == field(row, ^relationship.destination_field)
      )

    add_binding(new_query, [relationship.name], :inner)
  end

  defp do_join_relationship(query, [%{type: :many_to_many} = relationship], :left) do
    relationship_through = maybe_get_resource_query(relationship.through)
    relationship_destination = maybe_get_resource_query(relationship.destination)

    new_query =
      from(row in query,
        left_join: through in ^relationship_through,
        on:
          field(row, ^relationship.source_field) ==
            field(through, ^relationship.source_field_on_join_table),
        left_join: destination in ^relationship_destination,
        on:
          field(destination, ^relationship.destination_field) ==
            field(through, ^relationship.destination_field_on_join_table)
      )

    join_path = [String.to_existing_atom(to_string(relationship.name) <> "_join_assoc")]
    full_path = [relationship.name]

    new_query
    |> add_binding(join_path, :left)
    |> add_binding(full_path, :left)
  end

  defp do_join_relationship(query, [relationship], :left) do
    relationship_destination = maybe_get_resource_query(relationship.destination)

    new_query =
      from(row in query,
        left_join: destination in ^relationship_destination,
        on: field(row, ^relationship.source_field) == field(row, ^relationship.destination_field)
      )

    add_binding(new_query, [relationship.name], :left)
  end

  defp add_filter_expression(query, filter) do
    {params, expr} = filter_to_expr(filter, query.__ash_bindings__.bindings, [])

    if expr do
      boolean_expr = %Ecto.Query.BooleanExpr{
        expr: expr,
        op: :and,
        params: params
      }

      %{query | wheres: [boolean_expr | query.wheres]}
    else
      query
    end
  end

  defp join_exprs(nil, nil, _op), do: nil
  defp join_exprs(expr, nil, _op), do: expr
  defp join_exprs(nil, expr, _op), do: expr
  defp join_exprs(left_expr, right_expr, op), do: {op, [], [left_expr, right_expr]}

  defp filter_to_expr(filter, bindings, params, current_binding \\ 0, path \\ []) do
    {params, not_expr} =
      case filter.not do
        nil ->
          {params, nil}

        not_filter ->
          filter_to_expr(not_filter, bindings, params)
      end

    {params, existing_expr} =
      Enum.reduce(filter.attributes, {params, not_expr}, fn {attribute, filter},
                                                            {params, existing_expr} ->
        {params, expr} = filter_value_to_expr(attribute, filter, current_binding, params)

        {params, join_exprs(existing_expr, expr, :and)}
      end)

    {params, expr} =
      Enum.reduce(filter.relationships, {params, existing_expr}, fn {relationship,
                                                                     relationship_filter},
                                                                    {params, existing_expr} ->
        full_path = path ++ [relationship]

        binding = Map.get(bindings, full_path) || raise "unbound relationship referenced!"

        {params, expr} =
          filter_to_expr(relationship_filter, bindings, params, binding.binding, full_path)

        {params, join_exprs(expr, existing_expr, :and)}
      end)

    Enum.reduce(filter.ors, {params, expr}, fn or_filter, {params, existing_expr} ->
      {params, expr} = filter_to_expr(or_filter, bindings, params, current_binding, path)

      {params, join_exprs(existing_expr, expr, :or)}
    end)
  end

  # THe fact that we keep counting params here is very silly.
  defp filter_value_to_expr(attribute, %Eq{value: value}, current_binding, params) do
    {params ++ [{value, {current_binding, attribute}}],
     {:==, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp filter_value_to_expr(attribute, %NotEq{value: value}, current_binding, params) do
    {params ++ [{value, {current_binding, attribute}}],
     {:==, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp filter_value_to_expr(attribute, %In{values: values}, current_binding, params) do
    {params ++ [{values, {:in, {current_binding, attribute}}}],
     {:in, [],
      [
        {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
        {:^, [], [Enum.count(params)]}
      ]}}
  end

  defp filter_value_to_expr(
         attribute,
         %NotIn{values: values},
         current_binding,
         params
       ) do
    {params ++ [{values, {:in, {current_binding, attribute}}}],
     {:not,
      {:in, [],
       [
         {{:., [], [{:&, [], [current_binding]}, attribute]}, [], []},
         {:^, [], [Enum.count(params)]}
       ]}}}
  end

  defp filter_value_to_expr(
         attribute,
         %And{left: left, right: right},
         current_binding,
         params
       ) do
    {params, left_expr} = filter_value_to_expr(attribute, left, current_binding, params)

    {params, right_expr} = filter_value_to_expr(attribute, right, current_binding, params)

    {params, join_exprs(left_expr, right_expr, :and)}
  end

  defp filter_value_to_expr(
         attribute,
         %Or{left: left, right: right},
         current_binding,
         params
       ) do
    {params, left_expr} = filter_value_to_expr(attribute, left, current_binding, params)

    {params, right_expr} = filter_value_to_expr(attribute, right, current_binding, params)

    {params, join_exprs(left_expr, right_expr, :or)}
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

  @impl true
  def can_query_async?(resource) do
    repo(resource).in_transaction?()
  end

  @impl true
  def transaction(resource, func) do
    repo(resource).transaction(func)
  end

  defp maybe_get_resource_query(resource) do
    if Ash.resource_module?(resource) do
      {resource.postgres_table(), resource}
    else
      resource
    end
  end
end
