defmodule AshPostgres.Migrator do
  @default_snapshot_path "priv/ash/resource_snapshots"

  import Mix.Generator

  defstruct snapshot_path: @default_snapshot_path, init: false, migration_path: nil

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
    |> Enum.each(fn {repo, table, snapshot} ->
      repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()
      folder = Path.join(opts.snapshot_path, repo_name)
      file = Path.join(folder, table <> ".bin")

      migration_name = "#{timestamp()}_create_#{table}"

      migration_file =
        if opts.migration_path do
          opts.migration_path
        else
          "priv/"
          |> Path.join(repo_name)
          |> Path.join("migrations")
        end
        |> Path.join(migration_name <> ".exs")

      unless File.exists?(folder) do
        File.mkdir!(folder)
      end

      if File.exists?(file) do
        update_migration(file, repo, repo_name, table, snapshot, migration_file)
      else
        write_new_migration(file, repo, table, snapshot, migration_file)
      end
    end)
  end

  def write_new_migration(snapshot_file, repo, table, snapshot, migration_file) do
    snapshot_binary = snapshot_to_binary(snapshot)

    File.write!(snapshot_file, snapshot_binary)

    module_name = Module.concat([repo, Migrations, Macro.camelize("create_#{table}")])

    contents =
      new_migration_template(
        snapshot: snapshot,
        mod: module_name,
        repo: repo
      )

    create_file(
      migration_file,
      Code.format_string!(contents)
    )
  end

  def update_migration(snapshot_file, repo, repo_name, table, snapshot, migration_file) do
    current_snapshot =
      snapshot_file
      |> File.read!()
      |> :erlang.binary_to_term()

    module_name = Module.concat([repo, Migrations, Macro.camelize("create_#{table}")])

    attributes_to_add =
      Enum.reject(snapshot.attributes, fn attribute ->
        Enum.find(current_snapshot.attributes, &(&1.name == attribute.name))
      end)

    attributes_to_remove =
      Enum.reject(current_snapshot.attributes, fn attribute ->
        Enum.find(snapshot.attributes, &(&1.name == attribute.name))
      end)

    attributes_to_alter =
      Enum.filter(snapshot.attributes, fn attribute ->
        Enum.find(current_snapshot.attributes, &(&1.name == attribute.name && &1 != attribute))
      end)

    unique_indexes_to_remove =
      Enum.reject(current_snapshot.identities, &(&1 in snapshot.identities))

    unique_indexes_to_add = Enum.reject(snapshot.identities, &(&1 in current_snapshot.identities))

    contents =
      update_migration_template(
        attributes_to_add: attributes_to_add,
        attributes_to_remove: attributes_to_remove,
        attributes_to_alter: attributes_to_alter,
        unique_indexes_to_remove: unique_indexes_to_remove,
        unique_indexes_to_add: unique_indexes_to_add,
        table: snapshot.table,
        mod: module_name,
        repo: repo
      )
      |> IO.inspect()
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  def get_snapshot(resource) do
    %{
      attributes: attributes(resource),
      identities: identities(resource),
      table: AshPostgres.table(resource),
      repo: AshPostgres.repo(resource)
    }
  end

  def attributes(resource) do
    resource
    |> Ash.Resource.attributes()
    |> Enum.sort_by(& &1.name)
  end

  defp identities(resource) do
    resource
    |> Ash.Resource.identities()
    |> Enum.filter(fn identity ->
      Enum.all?(identity.keys, fn key ->
        Ash.Resource.attribute(resource, key)
      end)
    end)
    |> Enum.sort_by(& &1.name)
  end

  embed_template(:new_migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration
    def change do
      create table(:<%= @snapshot.table %>) do
        <%= for attribute <- @snapshot.attributes do %>
          add :<%= attribute.name %>, <%= migration_type(Ash.Type.storage_type(attribute.type)) %>, null: <%= attribute.allow_nil? %>, default: <%= default(attribute, @repo) %> <% end %>

        <%= for identity <- @snapshot.identities do %>
          create unique_index(<%= inspect(identity.name) %>, [<%= unique_index_keys(identity.keys) %>]) <% end %>
      end
    end
  end
  """)

  embed_template(:update_migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration
    def change do
      alter table(:<%= @table %>) do
      end
    end
  end
  """)

  defp unique_index_keys(keys) do
    Enum.map_join(keys, ",", &inspect/1)
  end

  defp migration_type(:string), do: inspect(:text)
  defp migration_type(:integer), do: inspect(:integer)
  defp migration_type(:boolean), do: inspect(:boolean)
  defp migration_type(:binary_id), do: inspect(:binary_id)

  if :erlang.function_exported(Ash, :uuid, 0) do
    @uuid_functions [&Ash.uuid/0, &Ecto.UUID.generate/0]
  else
    @uuid_functions [&Ecto.UUID.generate/0]
  end

  defp default(%{default: default}, repo) when is_function(default) do
    cond do
      default in @uuid_functions && "uuid-ossp" in repo.config()[:installed_extensions] ->
        "fragment(\"uuid_generate_v4()\")"

      default == (&DateTime.utc_now/0) ->
        "fragment(\"now()\")"

      true ->
        "nil"
    end
  end

  defp default(%{default: {_, _, _}}, _), do: "nil"

  defp default(%{default: value, type: type}, _) do
    case Ash.Type.dump_to_native(type, value) do
      {:ok, value} -> inspect(value)
      _ -> "nil"
    end
  end

  defp snapshot_to_binary(snapshot) do
    :erlang.term_to_binary(snapshot)
  end
end
