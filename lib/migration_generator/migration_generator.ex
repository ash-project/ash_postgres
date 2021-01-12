defmodule AshPostgres.MigrationGenerator do
  @moduledoc """
  Generates migrations based on resource snapshots

  See `Mix.Tasks.AshPostgres.GenerateMigrations` for more information.
  """
  @default_snapshot_path "priv/resource_snapshots"

  import Mix.Generator

  alias AshPostgres.MigrationGenerator.{Operation, Phase}

  defstruct snapshot_path: @default_snapshot_path,
            migration_path: nil,
            tenant_migration_path: nil,
            quiet: false,
            format: true,
            dry_run: false,
            check_generated: false,
            drop_columns: false

  def generate(apis, opts \\ []) do
    apis = List.wrap(apis)

    opts =
      case struct(__MODULE__, opts) do
        %{check_generated: true} = opts ->
          %{opts | dry_run: true}

        opts ->
          opts
      end

    {tenant_snapshots, snapshots} =
      apis
      |> Enum.flat_map(&Ash.Api.resources/1)
      |> Enum.filter(&(Ash.Resource.data_layer(&1) == AshPostgres.DataLayer))
      |> Enum.filter(&AshPostgres.migrate?/1)
      |> Enum.map(&get_snapshot/1)
      |> Enum.split_with(&(&1.multitenancy.strategy == :context))

    tenant_snapshots_to_include_in_global =
      tenant_snapshots
      |> Enum.filter(& &1.multitenancy.global)
      |> Enum.map(&Map.put(&1, :multitenancy, %{strategy: nil, attribute: nil, global: false}))

    snapshots = snapshots ++ tenant_snapshots_to_include_in_global

    create_migrations(tenant_snapshots, opts, true)
    create_migrations(snapshots, opts, false)
  end

  defp create_migrations(snapshots, opts, tenant?) do
    snapshots
    |> Enum.group_by(& &1.repo)
    |> Enum.each(fn {repo, snapshots} ->
      deduped = deduplicate_snapshots(snapshots, opts)

      snapshots = Enum.map(deduped, &elem(&1, 0))

      deduped
      |> fetch_operations(opts)
      |> Enum.uniq()
      |> case do
        [] ->
          tenant_str =
            if tenant? do
              "tenant "
            else
              ""
            end

          Mix.shell().info(
            "No #{tenant_str}changes detected, so no migrations or snapshots have been created."
          )

          :ok

        operations ->
          if opts.check_generated, do: exit({:shutdown, 1})

          operations
          |> sort_operations()
          |> streamline()
          |> group_into_phases()
          |> comment_out_phases()
          |> build_up_and_down()
          |> write_migration!(snapshots, repo, opts, tenant?)
      end
    end)
  end

  defp comment_out_phases(phases) do
    Enum.map(phases, fn
      %{operations: operations} = phase ->
        if Enum.all?(operations, &match?(%{commented?: true}, &1)) do
          %{phase | commented?: true}
        else
          phase
        end

      phase ->
        phase
    end)
  end

  defp deduplicate_snapshots(snapshots, opts) do
    snapshots
    |> Enum.group_by(fn snapshot ->
      snapshot.table
    end)
    |> Enum.map(fn {_table, [snapshot | _] = snapshots} ->
      existing_snapshot = get_existing_snapshot(snapshot, opts)
      {primary_key, identities} = merge_primary_keys(existing_snapshot, snapshots)

      attributes = Enum.flat_map(snapshots, & &1.attributes)

      snapshot_identities =
        snapshots
        |> Enum.map(& &1.identities)
        |> Enum.concat()

      new_snapshot = %{
        snapshot
        | attributes: merge_attributes(attributes, snapshot.table),
          identities: snapshot_identities
      }

      all_identities =
        new_snapshot.identities
        |> Kernel.++(identities)
        |> Enum.sort_by(& &1.name)
        # We sort the identities by there being an identity with a matching name in the existing snapshot
        # so that we prefer identities that currently exist over new ones
        |> Enum.sort_by(fn identity ->
          existing_snapshot
          |> Kernel.||(%{})
          |> Map.get(:identities, [])
          |> Enum.any?(fn existing_identity ->
            existing_identity.name == identity.name
          end)
          |> Kernel.!()
        end)
        |> Enum.uniq_by(fn identity ->
          {Enum.sort(identity.keys), identity.base_filter}
        end)

      new_snapshot = %{new_snapshot | identities: all_identities}

      {
        %{
          new_snapshot
          | attributes:
              Enum.map(new_snapshot.attributes, fn attribute ->
                if attribute.name in primary_key do
                  %{attribute | primary_key?: true}
                else
                  %{attribute | primary_key?: false}
                end
              end)
        },
        existing_snapshot
      }
    end)
  end

  defp merge_attributes(attributes, table) do
    attributes
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn
      {_name, [attribute]} ->
        attribute

      {name, attributes} ->
        %{
          name: name,
          type: merge_types(Enum.map(attributes, & &1.type), name, table),
          default: merge_defaults(Enum.map(attributes, & &1.default)),
          allow_nil?: Enum.any?(attributes, & &1.allow_nil?),
          references: merge_references(Enum.map(attributes, & &1.references), name, table),
          primary_key?: false
        }
    end)
  end

  defp merge_references(references, name, table) do
    references
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        nil

      [reference] ->
        reference

      references ->
        conflicting_table_field_names =
          Enum.map_join(references, "\n", fn reference ->
            "* #{reference.table}.#{reference.destination_field}"
          end)

        raise "Conflicting references for `#{table}.#{name}`:\n#{conflicting_table_field_names}"
    end
  end

  defp merge_types(types, name, table) do
    types
    |> Enum.uniq()
    |> case do
      [type] ->
        type

      types ->
        raise "Conflicting types for table `#{table}.#{name}`: #{inspect(types)}"
    end
  end

  defp merge_defaults(defaults) do
    defaults
    |> Enum.uniq()
    |> case do
      [default] -> default
      _ -> "nil"
    end
  end

  defp merge_primary_keys(nil, [snapshot | _] = snapshots) do
    snapshots
    |> Enum.map(&pkey_names(&1.attributes))
    |> Enum.uniq()
    |> case do
      [pkey_names] ->
        {pkey_names, []}

      unique_primary_keys ->
        unique_primary_key_names =
          unique_primary_keys
          |> Enum.with_index()
          |> Enum.map_join("\n", fn {pkey, index} ->
            "#{index}: #{inspect(pkey)}"
          end)

        message = """
        Which primary key should be used for the table `#{snapshot.table}` (enter the number)?

        #{unique_primary_key_names}
        """

        choice =
          message
          |> Mix.shell().prompt()
          |> String.to_integer()

        identities =
          unique_primary_keys
          |> List.delete_at(choice)
          |> Enum.map(fn pkey_names ->
            pkey_name_string = Enum.join(pkey_names, "_")
            name = snapshot.table <> "_" <> pkey_name_string

            %{
              keys: pkey_names,
              name: name
            }
          end)

        primary_key = Enum.sort(Enum.at(unique_primary_keys, choice))

        identities =
          Enum.reject(identities, fn identity ->
            Enum.sort(identity.keys) == primary_key
          end)

        {primary_key, identities}
    end
  end

  defp merge_primary_keys(existing_snapshot, snapshots) do
    pkey_names = pkey_names(existing_snapshot.attributes)

    one_pkey_exists? =
      Enum.any?(snapshots, fn snapshot ->
        pkey_names(snapshot.attributes) == pkey_names
      end)

    if one_pkey_exists? do
      identities =
        snapshots
        |> Enum.map(&pkey_names(&1.attributes))
        |> Enum.uniq()
        |> Enum.reject(&(&1 == pkey_names))
        |> Enum.map(fn pkey_names ->
          pkey_name_string = Enum.join(pkey_names, "_")
          name = existing_snapshot.table <> "_" <> pkey_name_string

          %{
            keys: pkey_names,
            name: name
          }
        end)

      {pkey_names, identities}
    else
      merge_primary_keys(nil, snapshots)
    end
  end

  defp pkey_names(attributes) do
    attributes
    |> Enum.filter(& &1.primary_key?)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp write_migration!({up, down}, snapshots, repo, opts, tenant?) do
    repo_name = repo |> Module.split() |> List.last() |> Macro.underscore()

    migration_path =
      if tenant? do
        if opts.tenant_migration_path do
          opts.tenant_migration_path
        else
          "priv/"
        end
        |> Path.join(repo_name)
        |> Path.join("tenant_migrations")
      else
        if opts.migration_path do
          opts.migration_path
        else
          "priv/"
        end
        |> Path.join(repo_name)
        |> Path.join("migrations")
      end

    count =
      migration_path
      |> Path.join("*_migrate_resources*")
      |> Path.wildcard()
      |> Enum.count()
      |> Kernel.+(1)

    migration_name = "#{timestamp()}_migrate_resources#{count}"

    migration_file =
      migration_path
      |> Path.join(migration_name <> ".exs")

    module_name =
      if tenant? do
        Module.concat([repo, TenantMigrations, Macro.camelize("migrate_resources#{count}")])
      else
        Module.concat([repo, Migrations, Macro.camelize("migrate_resources#{count}")])
      end

    up =
      if tenant? do
        """
        tenants =
          if prefix() do
            [prefix()]
          else
            repo().all_tenants()
          end

        for prefix <- tenants do
          #{up}
        end
        """
      else
        up
      end

    down =
      if tenant? do
        """
        tenants =
          if prefix() do
            [prefix()]
          else
            repo().all_tenants()
          end

        for prefix <- tenants do
          #{down}
        end
        """
      else
        down
      end

    contents = """
    defmodule #{inspect(module_name)} do
      @moduledoc \"\"\"
      Updates resources based on their most recent snapshots.

      This file was autogenerated with `mix ash_postgres.generate_migrations`
      \"\"\"

      use Ecto.Migration

      def up do
        #{up}
      end

      def down do
        #{down}
      end
    end
    """

    try do
      contents = format(contents, opts)

      create_new_snapshot(snapshots, repo_name, opts, tenant?)

      if opts.dry_run do
        Mix.shell().info(contents)
      else
        create_file(migration_file, contents)
      end
    rescue
      exception ->
        reraise(
          """
          Exception while formatting generated code:
          #{Exception.format(:error, exception, __STACKTRACE__)}

          Code:

          #{add_line_numbers(contents)}

          To generate it unformatted anyway, but manually fix it, use the `--no-format` option.
          """,
          __STACKTRACE__
        )
    end
  end

  defp add_line_numbers(contents) do
    lines = String.split(contents, "\n")

    digits = String.length(to_string(Enum.count(lines)))

    lines
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, index} ->
      "#{String.pad_trailing(to_string(index), digits, " ")} | #{line}"
    end)
  end

  defp create_new_snapshot(snapshots, repo_name, opts, tenant?) do
    unless opts.dry_run do
      Enum.each(snapshots, fn snapshot ->
        snapshot_binary = snapshot_to_binary(snapshot)

        snapshot_folder =
          if tenant? do
            opts.snapshot_path
            |> Path.join(repo_name)
            |> Path.join("tenants")
          else
            opts.snapshot_path
            |> Path.join(repo_name)
          end

        snapshot_file = Path.join(snapshot_folder, "#{snapshot.table}/#{timestamp()}.json")

        File.mkdir_p(Path.dirname(snapshot_file))
        File.write!(snapshot_file, snapshot_binary, [])

        old_snapshot_folder = Path.join(snapshot_folder, "#{snapshot.table}.json")

        if File.exists?(old_snapshot_folder) do
          new_snapshot_folder = Path.join(snapshot_folder, "#{snapshot.table}/initial.json")
          File.rename(old_snapshot_folder, new_snapshot_folder)
        end
      end)
    end
  end

  defp build_up_and_down(phases) do
    up =
      Enum.map_join(phases, "\n", fn phase ->
        phase
        |> phase.__struct__.up()
        |> Kernel.<>("\n")
        |> maybe_comment(phase)
      end)

    down =
      phases
      |> Enum.reverse()
      |> Enum.map_join("\n", fn phase ->
        phase
        |> phase.__struct__.down()
        |> Kernel.<>("\n")
        |> maybe_comment(phase)
      end)

    {up, down}
  end

  defp maybe_comment(text, %{commented?: true}) do
    text
    |> String.split("\n")
    |> Enum.map(fn line ->
      if String.starts_with?(line, "#") do
        line
      else
        "# #{line}"
      end
    end)
    |> Enum.join("\n")
  end

  defp maybe_comment(text, _), do: text

  defp format(string, opts) do
    if opts.format do
      Code.format_string!(string, locals_without_parens: ecto_sql_locals_without_parens())
    else
      string
    end
  rescue
    exception ->
      IO.puts("""
      Exception while formatting:

      #{inspect(exception)}

      #{inspect(string)}
      """)

      reraise exception, __STACKTRACE__
  end

  defp ecto_sql_locals_without_parens do
    path = File.cwd!() |> Path.join("deps/ecto_sql/.formatter.exs")

    if File.exists?(path) do
      {opts, _} = Code.eval_file(path)
      Keyword.get(opts, :locals_without_parens, [])
    else
      []
    end
  end

  defp streamline(ops, acc \\ [])
  defp streamline([], acc), do: Enum.reverse(acc)

  defp streamline(
         [
           %Operation.AddAttribute{
             attribute: %{
               name: name
             },
             table: table
           } = add
           | rest
         ],
         acc
       ) do
    rest
    |> Enum.take_while(fn op ->
      op.table == table
    end)
    |> Enum.with_index()
    |> Enum.find(fn
      {%Operation.AlterAttribute{
         new_attribute: %{name: ^name, references: references},
         old_attribute: %{name: ^name}
       }, _}
      when not is_nil(references) ->
        true

      _ ->
        false
    end)
    |> case do
      nil ->
        streamline(rest, [add | acc])

      {alter, index} ->
        new_attribute = Map.put(add.attribute, :references, alter.new_attribute.references)
        streamline(List.delete_at(rest, index), [%{add | attribute: new_attribute} | acc])
    end
  end

  defp streamline([first | rest], acc) do
    streamline(rest, [first | acc])
  end

  defp group_into_phases(ops, current \\ nil, acc \\ [])

  defp group_into_phases([], nil, acc), do: Enum.reverse(acc)

  defp group_into_phases([], phase, acc) do
    phase = %{phase | operations: Enum.reverse(phase.operations)}
    Enum.reverse([phase | acc])
  end

  defp group_into_phases(
         [%Operation.CreateTable{table: table, multitenancy: multitenancy} | rest],
         nil,
         acc
       ) do
    group_into_phases(rest, %Phase.Create{table: table, multitenancy: multitenancy}, acc)
  end

  defp group_into_phases(
         [%Operation.AddAttribute{table: table} = op | rest],
         %{table: table} = phase,
         acc
       ) do
    group_into_phases(rest, %{phase | operations: [op | phase.operations]}, acc)
  end

  defp group_into_phases(
         [%Operation.AlterAttribute{table: table} = op | rest],
         %Phase.Alter{table: table} = phase,
         acc
       ) do
    group_into_phases(rest, %{phase | operations: [op | phase.operations]}, acc)
  end

  defp group_into_phases(
         [%Operation.RenameAttribute{table: table} = op | rest],
         %Phase.Alter{table: table} = phase,
         acc
       ) do
    group_into_phases(rest, %{phase | operations: [op | phase.operations]}, acc)
  end

  defp group_into_phases(
         [%Operation.RemoveAttribute{table: table} = op | rest],
         %{table: table} = phase,
         acc
       ) do
    group_into_phases(rest, %{phase | operations: [op | phase.operations]}, acc)
  end

  defp group_into_phases([%{no_phase: true} = op | rest], nil, acc) do
    group_into_phases(rest, nil, [op | acc])
  end

  defp group_into_phases([operation | rest], nil, acc) do
    phase = %Phase.Alter{
      operations: [operation],
      multitenancy: operation.multitenancy,
      table: operation.table
    }

    group_into_phases(rest, phase, acc)
  end

  defp group_into_phases(operations, phase, acc) do
    phase = %{phase | operations: Enum.reverse(phase.operations)}
    group_into_phases(operations, nil, [phase | acc])
  end

  defp sort_operations(ops, acc \\ [])
  defp sort_operations([], acc), do: acc

  defp sort_operations([op | rest], []), do: sort_operations(rest, [op])

  defp sort_operations([op | rest], acc) do
    acc = Enum.reverse(acc)

    after_index = Enum.find_index(acc, &after?(op, &1))

    new_acc =
      if after_index do
        acc
        |> List.insert_at(after_index, op)
        |> Enum.reverse()
      else
        [op | Enum.reverse(acc)]
      end

    sort_operations(rest, new_acc)
  end

  defp after?(
         %Operation.AddUniqueIndex{
           identity: %{keys: keys},
           table: table,
           multitenancy: multitenancy
         },
         %Operation.AddAttribute{table: table, attribute: %{name: name}}
       ) do
    name in keys || (multitenancy.attribute && name == multitenancy.attribute)
  end

  defp after?(%Operation.AddUniqueIndex{table: table}, %Operation.RemoveUniqueIndex{table: table}),
    do: true

  defp after?(
         %Operation.AddUniqueIndex{identity: %{keys: keys}, table: table},
         %Operation.AlterAttribute{table: table, new_attribute: %{name: name}}
       ) do
    name in keys
  end

  defp after?(
         %Operation.AddUniqueIndex{identity: %{keys: keys}, table: table},
         %Operation.RenameAttribute{table: table, new_attribute: %{name: name}}
       ) do
    name in keys
  end

  defp after?(
         %Operation.RemoveUniqueIndex{identity: %{keys: keys}, table: table},
         %Operation.RemoveAttribute{table: table, attribute: %{name: name}}
       ) do
    name in keys
  end

  defp after?(
         %Operation.RemoveUniqueIndex{identity: %{keys: keys}, table: table},
         %Operation.RenameAttribute{table: table, old_attribute: %{name: name}}
       ) do
    name in keys
  end

  defp after?(%Operation.AlterAttribute{table: table}, %Operation.DropForeignKey{
         table: table,
         direction: :up
       }),
       do: true

  defp after?(
         %Operation.DropForeignKey{
           table: table,
           direction: :down
         },
         %Operation.AlterAttribute{table: table}
       ),
       do: true

  defp after?(%Operation.AddAttribute{table: table}, %Operation.CreateTable{table: table}) do
    true
  end

  defp after?(
         %Operation.AddAttribute{
           attribute: %{
             references: %{table: table, destination_field: name}
           }
         },
         %Operation.AddAttribute{table: table, attribute: %{name: name}}
       ),
       do: true

  defp after?(
         %Operation.AddAttribute{
           table: table,
           attribute: %{
             primary_key?: false
           }
         },
         %Operation.AddAttribute{table: table, attribute: %{primary_key?: true}}
       ),
       do: true

  defp after?(
         %Operation.AddAttribute{
           table: table,
           attribute: %{
             primary_key?: true
           }
         },
         %Operation.RemoveAttribute{table: table, attribute: %{primary_key?: true}}
       ),
       do: true

  defp after?(
         %Operation.AlterAttribute{
           table: table,
           new_attribute: %{primary_key?: false},
           old_attribute: %{primary_key?: true}
         },
         %Operation.AddAttribute{
           table: table,
           attribute: %{
             primary_key?: true
           }
         }
       ),
       do: true

  defp after?(
         %Operation.RemoveAttribute{attribute: %{name: name}, table: table},
         %Operation.AlterAttribute{
           old_attribute: %{references: %{table: table, destination_field: name}}
         }
       ),
       do: true

  defp after?(
         %Operation.AlterAttribute{
           new_attribute: %{
             references: %{table: table, destination_field: name}
           }
         },
         %Operation.AddAttribute{table: table, attribute: %{name: name}}
       ),
       do: true

  defp after?(%Operation.AddUniqueIndex{table: table}, %Operation.CreateTable{table: table}) do
    true
  end

  defp after?(%Operation.AlterAttribute{new_attribute: %{references: references}}, _)
       when not is_nil(references),
       do: true

  defp after?(_, _), do: false

  defp fetch_operations(snapshots, opts) do
    Enum.flat_map(snapshots, fn {snapshot, existing_snapshot} ->
      do_fetch_operations(snapshot, existing_snapshot, opts)
    end)
  end

  defp do_fetch_operations(snapshot, existing_snapshot, opts, acc \\ [])

  defp do_fetch_operations(snapshot, nil, opts, acc) do
    empty_snapshot = %{
      attributes: [],
      identities: [],
      table: snapshot.table,
      repo: snapshot.repo,
      multitenancy: %{
        attribute: nil,
        strategy: nil,
        global: false
      }
    }

    do_fetch_operations(snapshot, empty_snapshot, opts, [
      %Operation.CreateTable{
        table: snapshot.table,
        multitenancy: snapshot.multitenancy,
        old_multitenancy: empty_snapshot.multitenancy
      }
      | acc
    ])
  end

  defp do_fetch_operations(snapshot, old_snapshot, opts, acc) do
    attribute_operations = attribute_operations(snapshot, old_snapshot, opts)

    rewrite_all_identities? = changing_multitenancy_affects_identities?(snapshot, old_snapshot)

    unique_indexes_to_remove =
      if rewrite_all_identities? do
        old_snapshot.identities
      else
        Enum.reject(old_snapshot.identities, fn old_identity ->
          Enum.find(snapshot.identities, fn identity ->
            Enum.sort(old_identity.keys) == Enum.sort(identity.keys) &&
              old_identity.base_filter == identity.base_filter
          end)
        end)
      end
      |> Enum.map(fn identity ->
        %Operation.RemoveUniqueIndex{identity: identity, table: snapshot.table}
      end)

    unique_indexes_to_add =
      if rewrite_all_identities? do
        snapshot.identities
      else
        Enum.reject(snapshot.identities, fn identity ->
          Enum.find(old_snapshot.identities, fn old_identity ->
            Enum.sort(old_identity.keys) == Enum.sort(identity.keys) &&
              old_identity.base_filter == identity.base_filter
          end)
        end)
      end
      |> Enum.map(fn identity ->
        %Operation.AddUniqueIndex{
          identity: identity,
          table: snapshot.table
        }
      end)

    [unique_indexes_to_remove, attribute_operations, unique_indexes_to_add, acc]
    |> Enum.concat()
    |> Enum.map(&Map.put(&1, :multitenancy, snapshot.multitenancy))
    |> Enum.map(&Map.put(&1, :old_multitenancy, old_snapshot.multitenancy))
  end

  defp attribute_operations(snapshot, old_snapshot, opts) do
    attributes_to_add =
      Enum.reject(snapshot.attributes, fn attribute ->
        Enum.find(old_snapshot.attributes, &(&1.name == attribute.name))
      end)

    attributes_to_remove =
      Enum.reject(old_snapshot.attributes, fn attribute ->
        Enum.find(snapshot.attributes, &(&1.name == attribute.name))
      end)

    {attributes_to_add, attributes_to_remove, attributes_to_rename} =
      resolve_renames(attributes_to_add, attributes_to_remove)

    attributes_to_alter =
      snapshot.attributes
      |> Enum.map(fn attribute ->
        {attribute,
         Enum.find(old_snapshot.attributes, &(&1.name == attribute.name && &1 != attribute))}
      end)
      |> Enum.filter(&elem(&1, 1))

    rename_attribute_events =
      Enum.map(attributes_to_rename, fn {new, old} ->
        %Operation.RenameAttribute{new_attribute: new, old_attribute: old, table: snapshot.table}
      end)

    add_attribute_events =
      Enum.flat_map(attributes_to_add, fn attribute ->
        if attribute.references do
          [
            %Operation.AddAttribute{
              attribute: Map.delete(attribute, :references),
              table: snapshot.table
            },
            %Operation.AlterAttribute{
              old_attribute: Map.delete(attribute, :references),
              new_attribute: attribute,
              table: snapshot.table
            }
          ]
        else
          [
            %Operation.AddAttribute{
              attribute: attribute,
              table: snapshot.table
            }
          ]
        end
      end)

    alter_attribute_events =
      Enum.flat_map(attributes_to_alter, fn {new_attribute, old_attribute} ->
        if has_reference?(old_snapshot.multitenancy, old_attribute) and
             Map.get(old_attribute, :references) != Map.get(new_attribute, :references) do
          [
            %Operation.DropForeignKey{
              attribute: old_attribute,
              table: snapshot.table,
              multitenancy: old_snapshot.multitenancy,
              direction: :up
            },
            %Operation.AlterAttribute{
              new_attribute: new_attribute,
              old_attribute: old_attribute,
              table: snapshot.table
            },
            %Operation.DropForeignKey{
              attribute: new_attribute,
              table: snapshot.table,
              multitenancy: snapshot.multitenancy,
              direction: :down
            }
          ]
        else
          [
            %Operation.AlterAttribute{
              new_attribute: new_attribute,
              old_attribute: old_attribute,
              table: snapshot.table
            }
          ]
        end
      end)

    remove_attribute_events =
      Enum.map(attributes_to_remove, fn attribute ->
        %Operation.RemoveAttribute{
          attribute: attribute,
          table: snapshot.table,
          commented?: !opts.drop_columns
        }
      end)

    add_attribute_events ++
      alter_attribute_events ++ remove_attribute_events ++ rename_attribute_events
  end

  def changing_multitenancy_affects_identities?(snapshot, old_snapshot) do
    snapshot.multitenancy != old_snapshot.multitenancy
  end

  def has_reference?(multitenancy, attribute) do
    not is_nil(Map.get(attribute, :references)) and
      !(attribute.references.multitenancy &&
          attribute.references.multitenancy.strategy == :context &&
          (is_nil(multitenancy) || multitenancy.strategy == :attribute))
  end

  def get_existing_snapshot(snapshot, opts) do
    repo_name = snapshot.repo |> Module.split() |> List.last() |> Macro.underscore()

    folder =
      if snapshot.multitenancy.strategy == :context do
        opts.snapshot_path
        |> Path.join(repo_name)
        |> Path.join("tenants")
      else
        opts.snapshot_path
        |> Path.join(repo_name)
      end

    snapshot_folder = Path.join(folder, snapshot.table)

    if File.exists?(snapshot_folder) do
      snapshot_folder
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&String.trim_trailing(&1, ".json"))
      |> Enum.map(&Integer.parse/1)
      |> Enum.filter(fn
        {_int, remaining} ->
          remaining == ""

        :error ->
          false
      end)
      |> Enum.map(&elem(&1, 0))
      |> case do
        [] ->
          get_old_snapshot(folder, snapshot)

        timestamps ->
          timestamp = Enum.max(timestamps)
          snapshot_file = Path.join(snapshot_folder, "#{timestamp}.json")

          snapshot_file
          |> File.read!()
          |> load_snapshot()
      end
    else
      get_old_snapshot(folder, snapshot)
    end
  end

  defp get_old_snapshot(folder, snapshot) do
    old_snapshot_file = Path.join(folder, "#{snapshot.table}.json")
    # This is adapter code for the old version, where migrations were stored in a flat directory
    if File.exists?(old_snapshot_file) do
      old_snapshot_file
      |> File.read!()
      |> load_snapshot()
    end
  end

  defp resolve_renames(adding, []), do: {adding, [], []}

  defp resolve_renames([], removing), do: {[], removing, []}

  defp resolve_renames([adding], [removing]) do
    if Mix.shell().yes?("Are you renaming :#{removing.name} to :#{adding.name}?") do
      {[], [], [{adding, removing}]}
    else
      {[adding], [removing], []}
    end
  end

  defp resolve_renames(adding, [removing | rest]) do
    {new_adding, new_removing, new_renames} =
      if Mix.shell().yes?("Are you renaming :#{removing.name}?") do
        new_attribute = get_new_attribute(adding)

        {adding -- [new_attribute], [], [{new_attribute, removing}]}
      else
        {adding, [removing], []}
      end

    {rest_adding, rest_removing, rest_renames} = resolve_renames(new_adding, rest)

    {new_adding ++ rest_adding, new_removing ++ rest_removing, rest_renames ++ new_renames}
  end

  defp get_new_attribute(adding, tries \\ 3)

  defp get_new_attribute(_adding, 0) do
    raise "Could not get matching name after 3 attempts."
  end

  defp get_new_attribute(adding, tries) do
    name =
      Mix.shell().prompt(
        "What are you renaming it to?: #{Enum.map_join(adding, ", ", & &1.name)}"
      )

    case Enum.find(adding, &(to_string(&1.name) == name)) do
      nil -> get_new_attribute(adding, tries - 1)
      new_attribute -> new_attribute
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  def get_snapshot(resource) do
    snapshot = %{
      attributes: attributes(resource),
      identities: identities(resource),
      table: AshPostgres.table(resource),
      repo: AshPostgres.repo(resource),
      multitenancy: multitenancy(resource),
      base_filter: AshPostgres.base_filter_sql(resource)
    }

    hash =
      :sha256
      |> :crypto.hash(inspect(snapshot))
      |> Base.encode16()

    Map.put(snapshot, :hash, hash)
  end

  defp multitenancy(resource) do
    strategy = Ash.Resource.multitenancy_strategy(resource)
    attribute = Ash.Resource.multitenancy_attribute(resource)
    global = Ash.Resource.multitenancy_global?(resource)

    %{
      strategy: strategy,
      attribute: attribute,
      global: global
    }
  end

  defp attributes(resource) do
    repo = AshPostgres.repo(resource)

    resource
    |> Ash.Resource.attributes()
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&Map.take(&1, [:name, :type, :default, :allow_nil?, :generated?, :primary_key?]))
    |> Enum.map(fn attribute ->
      default = default(attribute, repo)

      attribute
      |> Map.put(:default, default)
      |> Map.update!(:type, fn type ->
        type
        |> Ash.Type.storage_type()
        |> migration_type()
      end)
    end)
    |> Enum.map(fn attribute ->
      references = find_reference(resource, attribute)

      Map.put(attribute, :references, references)
    end)
  end

  defp find_reference(resource, attribute) do
    Enum.find_value(Ash.Resource.relationships(resource), fn relationship ->
      if attribute.name == relationship.source_field && relationship.type == :belongs_to &&
           foreign_key?(relationship) do
        %{
          destination_field: relationship.destination_field,
          multitenancy: multitenancy(relationship.destination),
          table: AshPostgres.table(relationship.destination)
        }
      end
    end)
  end

  defp migration_type(:string), do: :text
  defp migration_type(other), do: other

  defp foreign_key?(relationship) do
    Ash.Resource.data_layer(relationship.source) == AshPostgres.DataLayer &&
      AshPostgres.repo(relationship.source) == AshPostgres.repo(relationship.destination)
  end

  defp identities(resource) do
    resource
    |> Ash.Resource.identities()
    |> case do
      [] ->
        []

      identities ->
        base_filter = Ash.Resource.base_filter(resource)

        if base_filter && !AshPostgres.base_filter_sql(resource) do
          raise """
          Currently, ash_postgres cannot translate your base_filter #{inspect(base_filter)} into sql. You must provide the `base_filter_sql` option, or skip unique indexes with `skip_unique_indexes`"
          """
        end

        identities
    end
    |> Enum.reject(fn identity ->
      identity.name in AshPostgres.skip_unique_indexes?(resource)
    end)
    |> Enum.filter(fn identity ->
      Enum.all?(identity.keys, fn key ->
        Ash.Resource.attribute(resource, key)
      end)
    end)
    |> Enum.map(fn identity ->
      %{identity | keys: Enum.sort(identity.keys)}
    end)
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&Map.take(&1, [:name, :keys]))
    |> Enum.map(&Map.put(&1, :base_filter, AshPostgres.base_filter_sql(resource)))
  end

  if :erlang.function_exported(Ash, :uuid, 0) do
    @uuid_functions [&Ash.uuid/0, &Ecto.UUID.generate/0]
  else
    @uuid_functions [&Ecto.UUID.generate/0]
  end

  defp default(%{default: default}, repo) when is_function(default) do
    cond do
      default in @uuid_functions && "uuid-ossp" in (repo.config()[:installed_extensions] || []) ->
        ~S[fragment("uuid_generate_v4()")]

      default == (&DateTime.utc_now/0) ->
        ~S[fragment("now()")]

      true ->
        "nil"
    end
  end

  defp default(%{default: {_, _, _}}, _), do: "nil"

  defp default(%{default: nil}, _), do: "nil"

  defp default(%{default: value, type: type}, _) do
    case Ash.Type.dump_to_native(type, value) do
      {:ok, value} -> inspect(value)
      _ -> "nil"
    end
  end

  defp snapshot_to_binary(snapshot) do
    Jason.encode!(snapshot, pretty: true)
  end

  defp load_snapshot(json) do
    json
    |> Jason.decode!(keys: :atoms!)
    |> Map.update!(:identities, fn identities ->
      Enum.map(identities, &load_identity/1)
    end)
    |> Map.update!(:attributes, fn attributes ->
      Enum.map(attributes, &load_attribute/1)
    end)
    |> Map.update!(:repo, &String.to_atom/1)
    |> Map.put_new(:multitenancy, %{
      attribute: nil,
      strategy: nil,
      global: false
    })
    |> Map.update!(:multitenancy, &load_multitenancy/1)
  end

  defp load_multitenancy(multitenancy) do
    multitenancy
    |> Map.update!(:strategy, fn strategy -> strategy && String.to_atom(strategy) end)
    |> Map.update!(:attribute, fn attribute -> attribute && String.to_atom(attribute) end)
  end

  defp load_attribute(attribute) do
    attribute
    |> Map.update!(:type, &String.to_atom/1)
    |> Map.update!(:name, &String.to_atom/1)
    |> Map.put_new(:default, "nil")
    |> Map.update!(:default, &(&1 || "nil"))
    |> Map.update!(:references, fn
      nil ->
        nil

      references ->
        references
        |> Map.update!(:destination_field, &String.to_atom/1)
        |> Map.put_new(:multitenancy, %{
          attribute: nil,
          strategy: nil,
          global: false
        })
        |> Map.update!(:multitenancy, &load_multitenancy/1)
    end)
  end

  defp load_identity(identity) do
    identity
    |> Map.update!(:name, &String.to_atom/1)
    |> Map.update!(:keys, fn keys ->
      keys
      |> Enum.map(&String.to_atom/1)
      |> Enum.sort()
    end)
    |> Map.put_new(:base_filter, nil)
  end
end
