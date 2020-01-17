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
    changeset = Map.update!(changeset, :action, fn
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
    IO.inspect(filter)
    {:ok, query}
    # filter
    # |> join_relationships()
    # |> Enum.flat_map(fn {key, filter} ->
    #   Enum.map(filter, fn {filter_type, value} ->
    #     {key, filter_type, value}
    #   end)
    # end)
    # |> Enum.reduce({:ok, query}, fn
    #   _, {:error, error} ->
    #     {:error, error}

    #   {key, filter_type, value}, {:ok, query} ->
    #     do_filter(query, key, filter_type, value)
    # end)
  end

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
