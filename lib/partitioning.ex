defmodule AshPostgres.Partitioning do
  @moduledoc false

  @doc """
  Create a new partition for a resource
  """
  def create_partition(resource, opts) do
    repo = AshPostgres.DataLayer.Info.repo(resource)

    resource
    |> AshPostgres.DataLayer.Info.partitioning_method()
    |> case do
      :range ->
        create_range_partition(repo, resource, opts)

      :list ->
        create_list_partition(repo, resource, opts)

      :hash ->
        create_hash_partition(repo, resource, opts)

      unsupported_method ->
        raise "Invalid partition method, got: #{unsupported_method}"
    end
  end

  @doc """
  Check if partition exists
  """
  def exists?(resource, opts) do
    repo = AshPostgres.DataLayer.Info.repo(resource)
    key = Keyword.fetch!(opts, :key)
    table = AshPostgres.DataLayer.Info.table(resource)
    partition_name = table <> "_" <> "#{key}"

    partition_exists?(repo, resource, partition_name)
  end

  # TBI
  defp create_range_partition(repo, resource, opts) do
  end

  defp create_list_partition(repo, resource, opts) do
    key = Keyword.fetch!(opts, :key)
    table = AshPostgres.DataLayer.Info.table(resource)
    partition_name = table <> "_" <> "#{key}"

    if partition_exists?(repo, resource, partition_name) do
      {:error, :allready_exists}
    else
      Ecto.Adapters.SQL.query(
        repo,
        "CREATE TABLE #{partition_name} PARTITION OF public.#{table} FOR VALUES IN (#{key})"
      )

      if partition_exists?(repo, resource, partition_name) do
        :ok
      else
        {:error, "Unable to create partition"}
      end
    end
  end

  # TBI
  defp create_hash_partition(repo, resource, opts) do
  end

  defp partition_exists?(repo, resource, parition_name) do
    %Postgrex.Result{} =
      result =
      repo
      |> Ecto.Adapters.SQL.query!(
        "select table_name from information_schema.tables t where t.table_schema = 'public' and t.table_name = $1",
        [parition_name]
      )

    result.num_rows > 0
  end
end
