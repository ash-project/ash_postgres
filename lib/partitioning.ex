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
    partition_name = partition_name(resource, opts)

    partition_exists?(repo, resource, partition_name, opts)
  end

  # TBI
  defp create_range_partition(_repo, _resource, _opts) do
  end

  defp create_list_partition(repo, resource, opts) do
    key = Keyword.fetch!(opts, :key)
    table = AshPostgres.DataLayer.Info.table(resource)
    partition_name = partition_name(resource, opts)

    schema =
      Keyword.get(opts, :tenant)
      |> tenant_schema(resource)

    if partition_exists?(repo, resource, partition_name, opts) do
      {:error, :allready_exists}
    else
      Ecto.Adapters.SQL.query(
        repo,
        "CREATE TABLE \"#{schema}\".\"#{partition_name}\" PARTITION OF \"#{schema}\".\"#{table}\" FOR VALUES IN ('#{key}')"
      )

      if partition_exists?(repo, resource, partition_name, opts) do
        :ok
      else
        {:error, "Unable to create partition"}
      end
    end
  end

  # TBI
  defp create_hash_partition(_repo, _resource, _opts) do
  end

  defp partition_exists?(repo, resource, parition_name, opts) do
    schema =
      Keyword.get(opts, :tenant)
      |> tenant_schema(resource)

    %Postgrex.Result{} =
      result =
      repo
      |> Ecto.Adapters.SQL.query!(
        "select table_name from information_schema.tables t where t.table_schema = $1 and t.table_name = $2",
        [schema, parition_name]
      )

    result.num_rows > 0
  end

  defp partition_name(resource, opts) do
    key = Keyword.fetch!(opts, :key)
    table = AshPostgres.DataLayer.Info.table(resource)
    "#{table}_#{key}"
  end

  defp tenant_schema(tenant, resource) do
    tenant
    |> Ash.ToTenant.to_tenant(resource)
    |> case do
      nil -> "public"
      tenant -> tenant
    end
  end
end
