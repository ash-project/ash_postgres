defmodule AshPostgres.Migrator do
  @default_snapshot_path "priv/ash/resource_snapshots"

  defstruct snapshot_path: @default_snapshot_path, init: false

  def take_snapshots(apis, opts \\ []) do
    apis = List.wrap(apis)
    opts = struct(__MODULE__, opts)

    cond do
      !File.exists?(opts.snapshot_path) and !opts.init ->
        Mix.raise("""
        Could not find snapshots directory.

        If this is your first time running the migrator
        add the `--init` flag to create it.
        """)

      opts.init ->
        File.mkdir_p!(opts.snapshot_path)

      true ->
        :ok
    end

    apis
    |> Enum.flat_map(&Ash.Api.resources/1)
    |> Enum.filter(&(Ash.Resource.data_layer(&1) == AshPostgres.DataLayer))
    |> Enum.map(&get_snapshot/1)
    |> Enum.group_by(&{&1.repo, &1.table})
    |> Enum.map(fn {{repo, table}, snapshots} ->
      snapshot =
        Enum.reduce(snapshots, %{}, fn snapshot, acc ->
          Map.merge(snapshot, acc, fn
            key, left, right when key in [:attributes, :identity] ->
              left ++ right

            _key, _left, right ->
              right
          end)
        end)

      {repo, table, snapshot}
    end)
  end

  def get_snapshot(resource) do
    repo = AshPostgres.repo(resource)

    %{
      attributes: attributes(resource, repo),
      identities: identities(resource),
      table: AshPostgres.table(resource),
      repo: to_string(repo)
    }
  end

  def attributes(resource, repo) do
    resource
    |> Ash.Resource.attributes()
    |> Enum.map(fn attribute ->
      %{
        name: attribute.name,
        type: to_string(attribute.type),
        allow_nil?: attribute.allow_nil?,
        default: default(attribute, repo)
      }
    end)
  end

  defp identities(resource) do
    resource
    |> Ash.Resource.identities()
    |> Enum.filter(fn identity ->
      Enum.all?(identity.keys, fn key ->
        Ash.Resource.attribute(resource, key)
      end)
    end)
    |> Enum.map(&Map.take(&1, [:name, :keys]))
  end

  if :erlang.function_exported(Ash, :uuid, 0) do
    @uuid_functions [&Ash.uuid/0, &Ecto.UUID.generate/0]
  else
    @uuid_functions [&Ecto.UUID.generate/0]
  end

  defp default(%{default: default}, repo) when is_function(default) do
    if default in @uuid_functions do
      if "uuid-ossp" in repo.config()[:installed_extensions] do
        {:fragment, "uid_generate_v4()"}
      end
    end
  end

  defp default(%{default: {_, _, _}}, _), do: nil

  defp default(%{default: value, type: type}, _) do
    case Ash.Type.dump_to_native(type, value) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  # def take_resource_snapshot(resource, %{snapshot_path: snapshot_path}) do
  #   file = File.open!(resource)
  # end
end
