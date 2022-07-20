defmodule AshPostgres.MigrationGenerator do
  @moduledoc """
  Generates migrations based on resource snapshots

  See `Mix.Tasks.AshPostgres.GenerateMigrations` for more information.
  """
  @default_snapshot_path "priv/resource_snapshots"

  require Logger

  import Mix.Generator

  alias AshPostgres.MigrationGenerator.{Operation, Phase}

  defstruct snapshot_path: @default_snapshot_path,
            migration_path: nil,
            name: nil,
            tenant_migration_path: nil,
            quiet: false,
            current_snapshots: nil,
            answers: [],
            no_shell?: false,
            format: true,
            dry_run: false,
            check: false,
            drop_columns: false

  def generate(apis, opts \\ []) do
    apis = List.wrap(apis)
    opts = opts(opts)

    all_resources = Enum.uniq(Enum.flat_map(apis, &Ash.Api.resources/1))

    {tenant_snapshots, snapshots} =
      all_resources
      |> Enum.filter(fn resource ->
        Ash.DataLayer.data_layer(resource) == AshPostgres.DataLayer &&
          AshPostgres.migrate?(resource)
      end)
      |> Enum.flat_map(&get_snapshots(&1, all_resources))
      |> Enum.split_with(&(&1.multitenancy.strategy == :context))

    tenant_snapshots_to_include_in_global =
      tenant_snapshots
      |> Enum.filter(& &1.multitenancy.global)
      |> Enum.map(&Map.put(&1, :multitenancy, %{strategy: nil, attribute: nil, global: nil}))

    snapshots = snapshots ++ tenant_snapshots_to_include_in_global

    repos =
      snapshots
      |> Enum.map(& &1.repo)
      |> Enum.uniq()

    Mix.shell().info("\nExtension Migrations: ")
    create_extension_migrations(repos, opts)
    Mix.shell().info("\nGenerating Tenant Migrations: ")
    create_migrations(tenant_snapshots, opts, true)
    Mix.shell().info("\nGenerating Migrations:")
    create_migrations(snapshots, opts, false)
  end

  @doc """
  A work in progress utility for getting snapshots.

  Does not support everything supported by the migration generator.
  """
  def take_snapshots(api, repo, only_resources \\ nil) do
    all_resources = api |> Ash.Api.resources() |> Enum.uniq()

    all_resources
    |> Enum.filter(fn resource ->
      Ash.DataLayer.data_layer(resource) == AshPostgres.DataLayer &&
        AshPostgres.repo(resource) == repo &&
        (is_nil(only_resources) || resource in only_resources)
    end)
    |> Enum.flat_map(&get_snapshots(&1, all_resources))
  end

  @doc """
  A work in progress utility for getting operations between snapshots.

  Does not support everything supported by the migration generator.
  """
  def get_operations_from_snapshots(old_snapshots, new_snapshots, opts \\ []) do
    opts = %{opts(opts) | no_shell?: true}

    old_snapshots = Enum.map(old_snapshots, &sanitize_snapshot/1)

    new_snapshots
    |> deduplicate_snapshots(opts, old_snapshots)
    |> fetch_operations(opts)
    |> Enum.flat_map(&elem(&1, 1))
    |> Enum.uniq()
    |> organize_operations()
  end

  defp opts(opts) do
    case struct(__MODULE__, opts) do
      %{check: true} = opts ->
        %{opts | dry_run: true}

      opts ->
        opts
    end
  end

  defp create_extension_migrations(repos, opts) do
    for repo <- repos do
      snapshot_file = Path.join(opts.snapshot_path, "extensions.json")

      installed_extensions =
        if File.exists?(snapshot_file) do
          snapshot_file
          |> File.read!()
          |> Jason.decode!()
        else
          []
        end

      to_install = List.wrap(repo.installed_extensions()) -- List.wrap(installed_extensions)

      if Enum.empty?(to_install) do
        Mix.shell().info("No extensions to install")
        :ok
      else
        {module, migration_name} =
          case to_install do
            [single] ->
              {"install_#{single}", "#{timestamp(true)}_install_#{single}_extension"}

            multiple ->
              {"install_#{Enum.count(multiple)}_extensions",
               "#{timestamp(true)}_install_#{Enum.count(multiple)}_extensions"}
          end

        migration_file =
          opts
          |> migration_path(repo)
          |> Path.join(migration_name <> ".exs")

        module_name = Module.concat([repo, Migrations, Macro.camelize(module)])

        install =
          Enum.map_join(to_install, "\n", fn
            "ash-functions" ->
              """
              execute(\"\"\"
              CREATE OR REPLACE FUNCTION ash_elixir_or(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE)
              AS $$ SELECT COALESCE(NULLIF($1, FALSE), $2) $$
              LANGUAGE SQL;
              \"\"\")

              execute(\"\"\"
              CREATE OR REPLACE FUNCTION ash_elixir_or(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE)
              AS $$ SELECT COALESCE($1, $2) $$
              LANGUAGE SQL;
              \"\"\")

              execute(\"\"\"
              CREATE OR REPLACE FUNCTION ash_elixir_and(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) AS $$
                SELECT CASE
                  WHEN $1 IS TRUE THEN $2
                  ELSE $1
                END $$
              LANGUAGE SQL;
              \"\"\")

              execute(\"\"\"
              CREATE OR REPLACE FUNCTION ash_elixir_and(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) AS $$
                SELECT CASE
                  WHEN $1 IS NOT NULL THEN $2
                  ELSE $1
                END $$
              LANGUAGE SQL;
              \"\"\")
              """

            extension ->
              "execute(\"CREATE EXTENSION IF NOT EXISTS \\\"#{extension}\\\"\")"
          end)

        uninstall =
          Enum.map_join(to_install, "\n", fn
            "ash-functions" ->
              "execute(\"DROP FUNCTION IF EXISTS ash_elixir_and(BOOLEAN, ANYCOMPATIBLE), ash_elixir_and(ANYCOMPATIBLE, ANYCOMPATIBLE), ash_elixir_or(ANYCOMPATIBLE, ANYCOMPATIBLE), ash_elixir_or(BOOLEAN, ANYCOMPATIBLE)\")"

            extension ->
              "# execute(\"DROP EXTENSION IF EXISTS \\\"#{extension}\\\"\")"
          end)

        contents = """
        defmodule #{inspect(module_name)} do
          @moduledoc \"\"\"
          Installs any extensions that are mentioned in the repo's `installed_extensions/0` callback

          This file was autogenerated with `mix ash_postgres.generate_migrations`
          \"\"\"

          use Ecto.Migration

          def up do
            #{install}
          end

          def down do
            # Uncomment this if you actually want to uninstall the extensions
            # when this migration is rolled back:
            #{uninstall}
          end
        end
        """

        snapshot_contents = Jason.encode!(repo.installed_extensions(), pretty: true)

        contents = format(contents, opts)
        create_file(snapshot_file, snapshot_contents, force: true)
        create_file(migration_file, contents)
      end
    end
  end

  defp create_migrations(snapshots, opts, tenant?) do
    snapshots
    |> Enum.group_by(& &1.repo)
    |> Enum.each(fn {repo, snapshots} ->
      deduped = deduplicate_snapshots(snapshots, opts)

      snapshots_with_operations =
        deduped
        |> fetch_operations(opts)
        |> Enum.map(&add_order_to_operations/1)

      snapshots = Enum.map(snapshots_with_operations, &elem(&1, 0))

      snapshots_with_operations
      |> Enum.flat_map(&elem(&1, 1))
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
          if opts.check do
            IO.puts("""
            Migrations would have been generated, but the --check flag was provided.

            To see what migration would have been generated, run with the `--dry-run`
            option instead. To generate those migrations, run without either flag.
            """)

            exit({:shutdown, 1})
          end

          operations
          |> organize_operations
          |> build_up_and_down()
          |> write_migration!(snapshots, repo, opts, tenant?)
      end
    end)
  end

  defp add_order_to_operations({snapshot, operations}) do
    operations_with_order = Enum.map(operations, &add_order_to_operation(&1, snapshot.attributes))

    {snapshot, operations_with_order}
  end

  defp add_order_to_operation(%{attribute: attribute} = op, attributes) do
    order = Enum.find_index(attributes, &(&1.source == attribute.source))
    attribute = Map.put(attribute, :order, order)

    %{op | attribute: attribute}
  end

  defp add_order_to_operation(%{new_attribute: attribute} = op, attributes) do
    order = Enum.find_index(attributes, &(&1.source == attribute.source))
    attribute = Map.put(attribute, :order, order)

    %{op | new_attribute: attribute}
  end

  defp add_order_to_operation(op, _), do: op

  defp organize_operations([]), do: []

  defp organize_operations(operations) do
    operations
    |> sort_operations()
    |> streamline()
    |> group_into_phases()
    |> comment_out_phases()
  end

  defp comment_out_phases(phases) do
    Enum.map(phases, fn
      %{operations: []} = phase ->
        phase

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

  defp deduplicate_snapshots(snapshots, opts, existing_snapshots \\ []) do
    snapshots
    |> Enum.group_by(fn snapshot ->
      {snapshot.table, snapshot.schema}
    end)
    |> Enum.map(fn {_table, [snapshot | _] = snapshots} ->
      existing_snapshot =
        if opts.no_shell? do
          Enum.find(existing_snapshots, &(&1.table == snapshot.table))
        else
          get_existing_snapshot(snapshot, opts)
        end

      {primary_key, identities} = merge_primary_keys(existing_snapshot, snapshots, opts)

      attributes = Enum.flat_map(snapshots, & &1.attributes)

      count_with_create =
        snapshots
        |> Enum.filter(& &1.has_create_action)
        |> Enum.count()

      snapshot_identities =
        snapshots
        |> Enum.map(& &1.identities)
        |> Enum.concat()

      new_snapshot = %{
        snapshot
        | attributes: merge_attributes(attributes, snapshot.table, count_with_create),
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
                if attribute.source in primary_key do
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

  defp merge_attributes(attributes, table, count) do
    attributes
    |> Enum.with_index()
    |> Enum.map(fn {attr, i} -> Map.put(attr, :order, i) end)
    |> Enum.group_by(& &1.source)
    |> Enum.map(fn {source, attributes} ->
      size =
        attributes
        |> Enum.map(& &1.size)
        |> Enum.filter(& &1)
        |> case do
          [] ->
            nil

          sizes ->
            Enum.max(sizes)
        end

      %{
        source: source,
        type: merge_types(Enum.map(attributes, & &1.type), source, table),
        size: size,
        default: merge_defaults(Enum.map(attributes, & &1.default)),
        allow_nil?: Enum.any?(attributes, & &1.allow_nil?) || Enum.count(attributes) < count,
        generated?: Enum.any?(attributes, & &1.generated?),
        references: merge_references(Enum.map(attributes, & &1.references), source, table),
        primary_key?: false,
        order: attributes |> Enum.map(& &1.order) |> Enum.min()
      }
    end)
    |> Enum.sort(&(&1.order < &2.order))
    |> Enum.map(&Map.drop(&1, [:order]))
  end

  defp merge_references(references, name, table) do
    references
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        nil

      references ->
        %{
          destination_field: merge_uniq!(references, table, :destination_field, name),
          destination_field_default:
            merge_uniq!(references, table, :destination_field_default, name),
          destination_field_generated:
            merge_uniq!(references, table, :destination_field_generated, name),
          multitenancy: merge_uniq!(references, table, :multitenancy, name),
          on_delete: merge_uniq!(references, table, :on_delete, name),
          on_update: merge_uniq!(references, table, :on_update, name),
          name: merge_uniq!(references, table, :name, name),
          table: merge_uniq!(references, table, :table, name),
          schema: merge_uniq!(references, table, :schema, name)
        }
    end
  end

  defp merge_uniq!(references, table, field, attribute) do
    references
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> case do
      [] ->
        nil

      [value] ->
        value

      values ->
        values = Enum.map_join(values, "\n", &"  * #{inspect(&1)}")

        raise """
        Conflicting configurations for references for #{table}.#{attribute}:

        Values:

        #{values}
        """
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

  defp merge_primary_keys(nil, [snapshot | _] = snapshots, opts) do
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

        choice =
          if opts.no_shell? do
            raise "Unimplemented: cannot resolve primary key ambiguity without shell input"
          else
            message = """
            Which primary key should be used for the table `#{snapshot.table}` (enter the number)?

            #{unique_primary_key_names}
            """

            message
            |> Mix.shell().prompt()
            |> String.to_integer()
          end

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

  defp merge_primary_keys(existing_snapshot, snapshots, opts) do
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
      merge_primary_keys(nil, snapshots, opts)
    end
  end

  defp pkey_names(attributes) do
    attributes
    |> Enum.filter(& &1.primary_key?)
    |> Enum.map(& &1.source)
    |> Enum.sort()
  end

  defp migration_path(opts, repo, tenant? \\ false) do
    repo_name = repo_name(repo)

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
  end

  defp repo_name(repo) do
    repo |> Module.split() |> List.last() |> Macro.underscore()
  end

  defp write_migration!({up, down}, snapshots, repo, opts, tenant?) do
    repo_name = repo_name(repo)

    migration_path = migration_path(opts, repo, tenant?)

    {migration_name, last_part} =
      if opts.name do
        {"#{timestamp(true)}_#{opts.name}", "#{opts.name}"}
      else
        count =
          migration_path
          |> Path.join("*_migrate_resources*")
          |> Path.wildcard()
          |> Enum.count()
          |> Kernel.+(1)

        {"#{timestamp(true)}_migrate_resources#{count}", "migrate_resources#{count}"}
      end

    migration_file =
      migration_path
      |> Path.join(migration_name <> ".exs")

    module_name =
      if tenant? do
        Module.concat([repo, TenantMigrations, Macro.camelize(last_part)])
      else
        Module.concat([repo, Migrations, Macro.camelize(last_part)])
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

  @doc false
  def build_up_and_down(phases) do
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
    |> Enum.map_join("\n", fn line ->
      if String.starts_with?(line, "#") do
        line
      else
        "# #{line}"
      end
    end)
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
               source: name
             },
             schema: schema,
             table: table
           } = add
           | rest
         ],
         acc
       ) do
    rest
    |> Enum.take_while(fn op ->
      op.table == table && op.schema == schema
    end)
    |> Enum.with_index()
    |> Enum.find(fn
      {%Operation.AlterAttribute{
         new_attribute: %{source: ^name, references: references},
         old_attribute: %{source: ^name}
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
         [
           %Operation.CreateTable{table: table, schema: schema, multitenancy: multitenancy} | rest
         ],
         nil,
         acc
       ) do
    group_into_phases(
      rest,
      %Phase.Create{table: table, schema: schema, multitenancy: multitenancy},
      acc
    )
  end

  defp group_into_phases(
         [%Operation.AddAttribute{table: table, schema: schema} = op | rest],
         %{table: table, schema: schema} = phase,
         acc
       ) do
    group_into_phases(rest, %{phase | operations: [op | phase.operations]}, acc)
  end

  defp group_into_phases(
         [%Operation.AlterAttribute{table: table, schema: schema} = op | rest],
         %Phase.Alter{table: table, schema: schema} = phase,
         acc
       ) do
    group_into_phases(rest, %{phase | operations: [op | phase.operations]}, acc)
  end

  defp group_into_phases(
         [%Operation.RenameAttribute{table: table, schema: schema} = op | rest],
         %Phase.Alter{table: table, schema: schema} = phase,
         acc
       ) do
    group_into_phases(rest, %{phase | operations: [op | phase.operations]}, acc)
  end

  defp group_into_phases(
         [%Operation.RemoveAttribute{table: table, schema: schema} = op | rest],
         %{table: table, schema: schema} = phase,
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
      table: operation.table,
      schema: operation.schema
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
         %Operation.AddAttribute{attribute: %{order: l}, table: table, schema: schema},
         %Operation.AddAttribute{attribute: %{order: r}, table: table, schema: schema}
       ),
       do: l > r

  defp after?(
         %Operation.RenameUniqueIndex{
           table: table,
           schema: schema
         },
         %{table: table, schema: schema}
       ) do
    true
  end

  defp after?(
         %Operation.AddUniqueIndex{
           table: table,
           schema: schema
         },
         %{table: table, schema: schema}
       ) do
    true
  end

  defp after?(
         %Operation.AddCheckConstraint{
           constraint: %{attribute: attribute_or_attributes},
           table: table,
           multitenancy: multitenancy,
           schema: schema
         },
         %Operation.AddAttribute{table: table, attribute: %{source: source}, schema: schema}
       ) do
    source in List.wrap(attribute_or_attributes) ||
      (multitenancy.attribute && multitenancy.attribute in List.wrap(attribute_or_attributes))
  end

  defp after?(
         %Operation.AddCustomIndex{
           table: table,
           schema: schema
         },
         %Operation.AddAttribute{table: table, schema: schema}
       ) do
    true
  end

  defp after?(
         %Operation.AddCheckConstraint{table: table, schema: schema},
         %Operation.RemoveCheckConstraint{
           table: table,
           schema: schema
         }
       ),
       do: true

  defp after?(
         %Operation.AddCheckConstraint{
           constraint: %{attribute: attribute_or_attributes},
           table: table,
           schema: schema
         },
         %Operation.AlterAttribute{table: table, new_attribute: %{source: source}, schema: schema}
       ) do
    source in List.wrap(attribute_or_attributes)
  end

  defp after?(
         %Operation.AddCheckConstraint{
           constraint: %{attribute: attribute_or_attributes},
           table: table,
           schema: schema
         },
         %Operation.RenameAttribute{
           table: table,
           new_attribute: %{source: source},
           schema: schema
         }
       ) do
    source in List.wrap(attribute_or_attributes)
  end

  defp after?(
         %Operation.RemoveUniqueIndex{table: table, schema: schema},
         %Operation.AddUniqueIndex{table: table, schema: schema}
       ) do
    false
  end

  defp after?(
         %Operation.RemoveUniqueIndex{table: table, schema: schema},
         %{table: table, schema: schema}
       ) do
    true
  end

  defp after?(
         %Operation.RemoveCheckConstraint{
           constraint: %{attribute: attributes},
           table: table,
           schema: schema
         },
         %Operation.RemoveAttribute{table: table, attribute: %{source: source}, schema: schema}
       ) do
    source in List.wrap(attributes)
  end

  defp after?(
         %Operation.RemoveCheckConstraint{
           constraint: %{attribute: attributes},
           table: table,
           schema: schema
         },
         %Operation.RenameAttribute{
           table: table,
           old_attribute: %{source: source},
           schema: schema
         }
       ) do
    source in List.wrap(attributes)
  end

  defp after?(%Operation.AlterAttribute{table: table, schema: schema}, %Operation.DropForeignKey{
         table: table,
         schema: schema,
         direction: :up
       }),
       do: true

  defp after?(
         %Operation.DropForeignKey{
           table: table,
           schema: schema,
           direction: :down
         },
         %Operation.AlterAttribute{table: table, schema: schema}
       ),
       do: true

  defp after?(%Operation.AddAttribute{table: table, schema: schema}, %Operation.CreateTable{
         table: table,
         schema: schema
       }) do
    true
  end

  defp after?(
         %Operation.AddAttribute{
           attribute: %{
             references: %{table: table, destination_field: name}
           }
         },
         %Operation.AddAttribute{table: table, attribute: %{source: name}}
       ),
       do: true

  defp after?(
         %Operation.AddAttribute{
           table: table,
           schema: schema,
           attribute: %{
             primary_key?: false
           }
         },
         %Operation.AddAttribute{schema: schema, table: table, attribute: %{primary_key?: true}}
       ),
       do: true

  defp after?(
         %Operation.AddAttribute{
           table: table,
           schema: schema,
           attribute: %{
             primary_key?: true
           }
         },
         %Operation.RemoveAttribute{
           schema: schema,
           table: table,
           attribute: %{primary_key?: true}
         }
       ),
       do: true

  defp after?(
         %Operation.AlterAttribute{
           table: table,
           schema: schema,
           new_attribute: %{primary_key?: false},
           old_attribute: %{primary_key?: true}
         },
         %Operation.AddAttribute{
           table: table,
           schema: schema,
           attribute: %{
             primary_key?: true
           }
         }
       ),
       do: true

  defp after?(
         %Operation.RemoveAttribute{attribute: %{source: source}, table: table},
         %Operation.AlterAttribute{
           old_attribute: %{
             references: %{table: table, destination_field: source}
           }
         }
       ),
       do: true

  defp after?(
         %Operation.AlterAttribute{
           new_attribute: %{
             references: %{table: table, destination_field: name}
           }
         },
         %Operation.AddAttribute{table: table, attribute: %{source: name}}
       ),
       do: true

  defp after?(%Operation.AddCheckConstraint{table: table, schema: schema}, %Operation.CreateTable{
         table: table,
         schema: schema
       }) do
    true
  end

  defp after?(
         %Operation.AlterAttribute{new_attribute: %{references: references}, table: table},
         %{table: table}
       )
       when not is_nil(references),
       do: true

  defp after?(%Operation.AddCheckConstraint{}, _), do: true
  defp after?(%Operation.RemoveCheckConstraint{}, _), do: true

  defp after?(_, _), do: false

  defp fetch_operations(snapshots, opts) do
    snapshots
    |> Enum.map(fn {snapshot, existing_snapshot} ->
      {snapshot, do_fetch_operations(snapshot, existing_snapshot, opts)}
    end)
    |> Enum.reject(fn {_, ops} ->
      Enum.empty?(ops)
    end)
  end

  defp do_fetch_operations(snapshot, existing_snapshot, opts, acc \\ [])

  defp do_fetch_operations(
         %{schema: new_schema} = snapshot,
         %{schema: old_schema},
         opts,
         []
       )
       when new_schema != old_schema do
    do_fetch_operations(snapshot, nil, opts, [])
  end

  defp do_fetch_operations(snapshot, nil, opts, acc) do
    empty_snapshot = %{
      attributes: [],
      identities: [],
      schema: nil,
      custom_indexes: [],
      check_constraints: [],
      table: snapshot.table,
      repo: snapshot.repo,
      base_filter: nil,
      multitenancy: %{
        attribute: nil,
        strategy: nil,
        global: nil
      }
    }

    do_fetch_operations(snapshot, empty_snapshot, opts, [
      %Operation.CreateTable{
        table: snapshot.table,
        schema: snapshot.schema,
        multitenancy: snapshot.multitenancy,
        old_multitenancy: empty_snapshot.multitenancy
      }
      | acc
    ])
  end

  defp do_fetch_operations(snapshot, old_snapshot, opts, acc) do
    attribute_operations = attribute_operations(snapshot, old_snapshot, opts)

    rewrite_all_identities? = changing_multitenancy_affects_identities?(snapshot, old_snapshot)

    custom_indexes_to_add =
      Enum.filter(snapshot.custom_indexes, fn index ->
        !Enum.find(old_snapshot.custom_indexes, fn old_custom_index ->
          old_custom_index == index
        end)
      end)
      |> Enum.map(fn custom_index ->
        %Operation.AddCustomIndex{
          index: custom_index,
          table: snapshot.table,
          schema: snapshot.schema,
          multitenancy: snapshot.multitenancy,
          base_filter: snapshot.base_filter
        }
      end)

    custom_indexes_to_remove =
      Enum.filter(old_snapshot.custom_indexes, fn old_custom_index ->
        rewrite_all_identities? ||
          !Enum.find(snapshot.custom_indexes, fn index ->
            old_custom_index == index
          end)
      end)
      |> Enum.map(fn custom_index ->
        %Operation.RemoveCustomIndex{
          index: custom_index,
          table: old_snapshot.table,
          schema: old_snapshot.schema,
          multitenancy: old_snapshot.multitenancy,
          base_filter: old_snapshot.base_filter
        }
      end)

    unique_indexes_to_remove =
      if rewrite_all_identities? do
        old_snapshot.identities
      else
        Enum.reject(old_snapshot.identities, fn old_identity ->
          Enum.find(snapshot.identities, fn identity ->
            identity.name == old_identity.name &&
              Enum.sort(old_identity.keys) == Enum.sort(identity.keys) &&
              old_identity.base_filter == identity.base_filter
          end)
        end)
      end
      |> Enum.map(fn identity ->
        %Operation.RemoveUniqueIndex{
          identity: identity,
          table: snapshot.table,
          schema: snapshot.schema
        }
      end)

    unique_indexes_to_rename =
      if rewrite_all_identities? do
        []
      else
        snapshot.identities
        |> Enum.map(fn identity ->
          Enum.find_value(old_snapshot.identities, fn old_identity ->
            if old_identity.name == identity.name &&
                 old_identity.index_name != identity.index_name do
              {old_identity, identity}
            end
          end)
        end)
        |> Enum.filter(& &1)
      end
      |> Enum.map(fn {old_identity, new_identity} ->
        %Operation.RenameUniqueIndex{
          old_identity: old_identity,
          new_identity: new_identity,
          schema: snapshot.schema,
          table: snapshot.table
        }
      end)

    unique_indexes_to_add =
      if rewrite_all_identities? do
        snapshot.identities
      else
        Enum.reject(snapshot.identities, fn identity ->
          Enum.find(old_snapshot.identities, fn old_identity ->
            old_identity.name == identity.name &&
              Enum.sort(old_identity.keys) == Enum.sort(identity.keys) &&
              old_identity.base_filter == identity.base_filter
          end)
        end)
      end
      |> Enum.map(fn identity ->
        %Operation.AddUniqueIndex{
          identity: identity,
          schema: snapshot.schema,
          table: snapshot.table
        }
      end)

    constraints_to_add =
      snapshot.check_constraints
      |> Enum.reject(fn constraint ->
        Enum.find(old_snapshot.check_constraints, fn old_constraint ->
          old_constraint.check == constraint.check && old_constraint.name == constraint.name
        end)
      end)
      |> Enum.map(fn constraint ->
        %Operation.AddCheckConstraint{
          constraint: constraint,
          table: snapshot.table,
          schema: snapshot.schema
        }
      end)

    constraints_to_remove =
      old_snapshot.check_constraints
      |> Enum.reject(fn old_constraint ->
        Enum.find(snapshot.check_constraints, fn constraint ->
          old_constraint.check == constraint.check && old_constraint.name == constraint.name
        end)
      end)
      |> Enum.map(fn old_constraint ->
        %Operation.RemoveCheckConstraint{
          constraint: old_constraint,
          table: old_snapshot.table,
          schema: old_snapshot.schema
        }
      end)

    [
      unique_indexes_to_remove,
      attribute_operations,
      unique_indexes_to_add,
      unique_indexes_to_rename,
      constraints_to_add,
      constraints_to_remove,
      custom_indexes_to_add,
      custom_indexes_to_remove,
      acc
    ]
    |> Enum.concat()
    |> Enum.map(&Map.put(&1, :multitenancy, snapshot.multitenancy))
    |> Enum.map(&Map.put(&1, :old_multitenancy, old_snapshot.multitenancy))
  end

  defp attribute_operations(snapshot, old_snapshot, opts) do
    attributes_to_add =
      Enum.reject(snapshot.attributes, fn attribute ->
        Enum.find(old_snapshot.attributes, &(&1.source == attribute.source))
      end)

    attributes_to_remove =
      Enum.reject(old_snapshot.attributes, fn attribute ->
        Enum.find(snapshot.attributes, &(&1.source == attribute.source))
      end)

    {attributes_to_add, attributes_to_remove, attributes_to_rename} =
      resolve_renames(snapshot.table, attributes_to_add, attributes_to_remove, opts)

    attributes_to_alter =
      snapshot.attributes
      |> Enum.map(fn attribute ->
        {attribute,
         Enum.find(
           old_snapshot.attributes,
           &(&1.source == attribute.source && attributes_unequal?(&1, attribute, snapshot.repo))
         )}
      end)
      |> Enum.filter(&elem(&1, 1))

    rename_attribute_events =
      Enum.map(attributes_to_rename, fn {new, old} ->
        %Operation.RenameAttribute{
          new_attribute: new,
          old_attribute: old,
          table: snapshot.table,
          schema: snapshot.schema
        }
      end)

    add_attribute_events =
      Enum.flat_map(attributes_to_add, fn attribute ->
        if attribute.references do
          [
            %Operation.AddAttribute{
              attribute: Map.delete(attribute, :references),
              schema: snapshot.schema,
              table: snapshot.table
            },
            %Operation.AlterAttribute{
              old_attribute: Map.delete(attribute, :references),
              new_attribute: attribute,
              schema: snapshot.schema,
              table: snapshot.table
            },
            %Operation.DropForeignKey{
              attribute: attribute,
              table: snapshot.table,
              schema: snapshot.schema,
              multitenancy: Map.get(attribute, :multitenancy),
              direction: :down
            }
          ]
        else
          [
            %Operation.AddAttribute{
              attribute: attribute,
              table: snapshot.table,
              schema: snapshot.schema
            }
          ]
        end
      end)

    alter_attribute_events =
      Enum.flat_map(attributes_to_alter, fn {new_attribute, old_attribute} ->
        if has_reference?(old_snapshot.multitenancy, old_attribute) and
             Map.get(old_attribute, :references) != Map.get(new_attribute, :references) do
          old_and_alter = [
            %Operation.DropForeignKey{
              attribute: old_attribute,
              table: snapshot.table,
              schema: snapshot.schema,
              multitenancy: old_snapshot.multitenancy,
              direction: :up
            },
            %Operation.AlterAttribute{
              new_attribute: new_attribute,
              old_attribute: old_attribute,
              schema: snapshot.schema,
              table: snapshot.table
            }
          ]

          if has_reference?(snapshot.multitenancy, new_attribute) do
            old_and_alter ++
              [
                %Operation.DropForeignKey{
                  attribute: new_attribute,
                  table: snapshot.table,
                  schema: snapshot.schema,
                  multitenancy: snapshot.multitenancy,
                  direction: :down
                }
              ]
          else
            old_and_alter
          end
        else
          [
            %Operation.AlterAttribute{
              new_attribute: Map.delete(new_attribute, :references),
              old_attribute: Map.delete(old_attribute, :references),
              schema: snapshot.schema,
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
          schema: snapshot.schema,
          commented?: !opts.drop_columns
        }
      end)

    add_attribute_events ++
      alter_attribute_events ++ remove_attribute_events ++ rename_attribute_events
  end

  # This exists to handle the fact that the remapping of the key name -> source caused attributes
  # to be considered unequal. We ignore things that only differ in that way using this function.
  defp attributes_unequal?(left, right, repo) do
    left = add_source_and_name_and_schema_and_ignore(left, repo)

    right = add_source_and_name_and_schema_and_ignore(right, repo)

    left != right
  end

  defp add_source_and_name_and_schema_and_ignore(attribute, repo) do
    cond do
      attribute[:source] ->
        Map.put(attribute, :name, attribute[:source])
        |> Map.update!(:source, &to_string/1)
        |> Map.update!(:name, &to_string/1)

      attribute[:name] ->
        attribute
        |> Map.put(:source, attribute[:name])
        |> Map.update!(:source, &to_string/1)
        |> Map.update!(:name, &to_string/1)

      true ->
        attribute
    end
    |> add_schema(repo)
    |> add_ignore()
  end

  defp add_ignore(%{references: references} = attribute) when is_map(references) do
    %{attribute | references: Map.put_new(references, :ignore?, false)}
  end

  defp add_ignore(attribute) do
    attribute
  end

  defp add_schema(%{references: references} = attribute, repo) when is_map(references) do
    schema = Map.get(references, :schema) || repo.config()[:default_prefix] || "public"

    %{
      attribute
      | references: Map.put(references, :schema, schema)
    }
  end

  defp add_schema(attribute, _) do
    attribute
  end

  def changing_multitenancy_affects_identities?(snapshot, old_snapshot) do
    snapshot.multitenancy != old_snapshot.multitenancy ||
      snapshot.base_filter != old_snapshot.base_filter
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

  T

  defp get_old_snapshot(folder, snapshot) do
    old_snapshot_file = Path.join(folder, "#{snapshot.table}.json")
    # This is adapter code for the old version, where migrations were stored in a flat directory
    if File.exists?(old_snapshot_file) do
      old_snapshot_file
      |> File.read!()
      |> load_snapshot()
    end
  end

  defp resolve_renames(_table, adding, [], _opts), do: {adding, [], []}

  defp resolve_renames(_table, [], removing, _opts), do: {[], removing, []}

  defp resolve_renames(table, [adding], [removing], opts) do
    if renaming_to?(table, removing.source, adding.source, opts) do
      {[], [], [{adding, removing}]}
    else
      {[adding], [removing], []}
    end
  end

  defp resolve_renames(table, adding, [removing | rest], opts) do
    {new_adding, new_removing, new_renames} =
      if renaming?(table, removing, opts) do
        new_attribute =
          if opts.no_shell? do
            raise "Unimplemented: Cannot get new_attribute without the shell!"
          else
            get_new_attribute(adding)
          end

        {adding -- [new_attribute], [], [{new_attribute, removing}]}
      else
        {adding, [removing], []}
      end

    {rest_adding, rest_removing, rest_renames} = resolve_renames(table, new_adding, rest, opts)

    {new_adding ++ rest_adding, new_removing ++ rest_removing, rest_renames ++ new_renames}
  end

  defp renaming_to?(table, removing, adding, opts) do
    if opts.no_shell? do
      raise "Unimplemented: cannot determine: Are you renaming #{table}.#{removing} to #{table}.#{adding}? without shell input"
    else
      Mix.shell().yes?("Are you renaming #{table}.#{removing} to #{table}.#{adding}?")
    end
  end

  defp renaming?(table, removing, opts) do
    if opts.no_shell? do
      raise "Unimplemented: cannot determine: Are you renaming #{table}.#{removing.source}? without shell input"
    else
      Mix.shell().yes?("Are you renaming #{table}.#{removing.source}?")
    end
  end

  defp get_new_attribute(adding, tries \\ 3)

  defp get_new_attribute(_adding, 0) do
    raise "Could not get matching name after 3 attempts."
  end

  defp get_new_attribute(adding, tries) do
    name =
      Mix.shell().prompt(
        "What are you renaming it to?: #{Enum.map_join(adding, ", ", & &1.source)}"
      )

    name =
      if name do
        String.trim(name)
      else
        nil
      end

    case Enum.find(adding, &(to_string(&1.source) == name)) do
      nil -> get_new_attribute(adding, tries - 1)
      new_attribute -> new_attribute
    end
  end

  defp timestamp(require_unique? \\ false) do
    # Alright, this is silly I know. But migration ids need to be unique
    # and "synthesizing" that behavior is significantly more annoying than
    # just waiting a bit, ensuring the migration versions are unique.
    if require_unique?, do: :timer.sleep(1500)
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  def get_snapshots(resource, all_resources) do
    Code.ensure_compiled!(AshPostgres.repo(resource))

    if AshPostgres.polymorphic?(resource) do
      all_resources
      |> Enum.flat_map(&Ash.Resource.Info.relationships/1)
      |> Enum.filter(&(&1.destination == resource))
      |> Enum.reject(&(&1.type == :belongs_to))
      |> Enum.filter(& &1.context[:data_layer][:table])
      |> Enum.uniq()
      |> Enum.map(fn relationship ->
        resource
        |> do_snapshot(
          relationship.context[:data_layer][:table],
          relationship.context[:data_layer][:schema]
        )
        |> Map.update!(:identities, fn identities ->
          identity_index_names = AshPostgres.identity_index_names(resource)

          Enum.map(identities, fn identity ->
            Map.put(
              identity,
              :index_name,
              identity_index_names[identity.name] ||
                "#{relationship.context[:data_layer][:table]}_#{identity.name}_index"
            )
          end)
        end)
        |> Map.update!(:attributes, fn attributes ->
          Enum.map(attributes, fn attribute ->
            destination_field_source =
              relationship.destination
              |> Ash.Resource.Info.attribute(relationship.destination_field)
              |> Map.get(:source)

            if attribute.source == destination_field_source do
              source_attribute =
                Ash.Resource.Info.attribute(relationship.source, relationship.source_field)

              Map.put(attribute, :references, %{
                destination_field: source_attribute.source,
                destination_field_default:
                  default(source_attribute, AshPostgres.repo(relationship.destination)),
                destination_field_generated: source_attribute.generated?,
                multitenancy: multitenancy(relationship.source),
                table: AshPostgres.table(relationship.source),
                schema: AshPostgres.schema(relationship.source),
                on_delete: AshPostgres.polymorphic_on_delete(relationship.source),
                on_update: AshPostgres.polymorphic_on_update(relationship.source),
                name:
                  AshPostgres.polymorphic_name(relationship.source) ||
                    "#{relationship.context[:data_layer][:table]}_#{destination_field_source}_fkey"
              })
            else
              attribute
            end
          end)
        end)
      end)
    else
      [do_snapshot(resource, AshPostgres.table(resource))]
    end
  end

  defp do_snapshot(resource, table, schema \\ nil) do
    snapshot = %{
      attributes: attributes(resource, table),
      identities: identities(resource),
      table: table || AshPostgres.table(resource),
      schema: schema || AshPostgres.schema(resource),
      check_constraints: check_constraints(resource),
      custom_indexes: custom_indexes(resource),
      repo: AshPostgres.repo(resource),
      multitenancy: multitenancy(resource),
      base_filter: AshPostgres.base_filter_sql(resource),
      has_create_action: has_create_action?(resource)
    }

    hash =
      :sha256
      |> :crypto.hash(inspect(snapshot))
      |> Base.encode16()

    Map.put(snapshot, :hash, hash)
  end

  defp has_create_action?(resource) do
    resource
    |> Ash.Resource.Info.actions()
    |> Enum.any?(&(&1.type == :create))
  end

  defp check_constraints(resource) do
    resource
    |> AshPostgres.check_constraints()
    |> Enum.filter(& &1.check)
    |> case do
      [] ->
        []

      constraints ->
        base_filter = Ash.Resource.Info.base_filter(resource)

        if base_filter && !AshPostgres.base_filter_sql(resource) do
          raise """
          Cannot create a check constraint for a resource with a base filter without also configuring `base_filter_sql`.

          You must provide the `base_filter_sql` option, or manually create add the check constraint to your migrations.
          """
        end

        constraints
    end
    |> Enum.map(fn constraint ->
      attributes =
        constraint.attribute
        |> List.wrap()
        |> Enum.map(fn attribute ->
          resource
          |> Ash.Resource.Info.attribute(attribute)
          |> Map.get(:source)
        end)

      %{
        name: constraint.name,
        attribute: attributes,
        check: constraint.check,
        base_filter: AshPostgres.base_filter_sql(resource)
      }
    end)
  end

  defp custom_indexes(resource) do
    resource
    |> AshPostgres.custom_indexes()
    |> Enum.map(fn custom_index ->
      Map.from_struct(custom_index)
    end)
  end

  defp multitenancy(resource) do
    strategy = Ash.Resource.Info.multitenancy_strategy(resource)
    attribute = Ash.Resource.Info.multitenancy_attribute(resource)
    global = Ash.Resource.Info.multitenancy_global?(resource)

    %{
      strategy: strategy,
      attribute: attribute,
      global: global
    }
  end

  defp attributes(resource, table) do
    repo = AshPostgres.repo(resource)

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.map(
      &Map.take(&1, [:name, :source, :type, :default, :allow_nil?, :generated?, :primary_key?])
    )
    |> Enum.map(fn attribute ->
      default = default(attribute, repo)

      type =
        AshPostgres.migration_types(resource)[attribute.name] || migration_type(attribute.type)

      type =
        if :erlang.function_exported(repo, :override_migration_type, 1) do
          repo.override_migration_type(type)
        else
          type
        end

      {type, size} =
        case type do
          {:varchar, size} ->
            {:varchar, size}

          {:binary, size} ->
            {:binary, size}

          other ->
            {other, nil}
        end

      attribute
      |> Map.put(:default, default)
      |> Map.put(:size, size)
      |> Map.put(:type, type)
      |> Map.put(:source, attribute.source || attribute.name)
      |> Map.delete(:name)
    end)
    |> Enum.map(fn attribute ->
      references = find_reference(resource, table, attribute)

      Map.put(attribute, :references, references)
    end)
  end

  defp find_reference(resource, table, attribute) do
    Enum.find_value(Ash.Resource.Info.relationships(resource), fn relationship ->
      source_field_name =
        relationship.source
        |> Ash.Resource.Info.attribute(relationship.source_field)
        |> then(fn attribute ->
          attribute.source || attribute.name
        end)

      if attribute.source == source_field_name && relationship.type == :belongs_to &&
           foreign_key?(relationship) do
        configured_reference =
          configured_reference(resource, table, attribute.source || attribute.name, relationship)

        unless Map.get(configured_reference, :ignore?) do
          destination_field_source =
            relationship.destination
            |> Ash.Resource.Info.attribute(relationship.destination_field)
            |> then(fn attribute ->
              attribute.source || attribute.name
            end)

          %{
            destination_field: destination_field_source,
            multitenancy: multitenancy(relationship.destination),
            on_delete: configured_reference.on_delete,
            on_update: configured_reference.on_update,
            name: configured_reference.name,
            schema:
              relationship.context[:data_layer][:schema] ||
                AshPostgres.schema(relationship.destination) ||
                AshPostgres.repo(relationship.destination).config()[:default_prefix],
            table:
              relationship.context[:data_layer][:table] ||
                AshPostgres.table(relationship.destination)
          }
        end
      end
    end)
  end

  defp configured_reference(resource, table, attribute, relationship) do
    ref =
      resource
      |> AshPostgres.references()
      |> Enum.find(&(&1.relationship == relationship.name))
      |> Kernel.||(%{
        on_delete: nil,
        on_update: nil,
        schema:
          relationship.context[:data_layer][:schema] ||
            AshPostgres.schema(relationship.destination) ||
            AshPostgres.repo(relationship.destination).config()[:default_prefix],
        name: nil,
        ignore?: false
      })

    Map.put(ref, :name, ref.name || "#{table}_#{attribute}_fkey")
  end

  defp migration_type({:array, type}), do: {:array, migration_type(type)}
  defp migration_type(Ash.Type.CiString), do: :citext
  defp migration_type(Ash.Type.UUID), do: :uuid
  defp migration_type(Ash.Type.Integer), do: :bigint
  defp migration_type(other), do: migration_type_from_storage_type(Ash.Type.storage_type(other))
  defp migration_type_from_storage_type(:string), do: :text
  defp migration_type_from_storage_type(storage_type), do: storage_type

  defp foreign_key?(relationship) do
    Ash.DataLayer.data_layer(relationship.source) == AshPostgres.DataLayer &&
      AshPostgres.repo(relationship.source) == AshPostgres.repo(relationship.destination)
  end

  defp identities(resource) do
    identity_index_names = AshPostgres.identity_index_names(resource)

    resource
    |> Ash.Resource.Info.identities()
    |> case do
      [] ->
        []

      identities ->
        base_filter = Ash.Resource.Info.base_filter(resource)

        if base_filter && !AshPostgres.base_filter_sql(resource) do
          raise """
          Cannot create a unique index for a resource with a base filter without also configuring `base_filter_sql`.

          You must provide the `base_filter_sql` option, or skip unique indexes with `skip_unique_indexes`"
          """
        end

        identities
    end
    |> Enum.reject(fn identity ->
      identity.name in AshPostgres.skip_unique_indexes?(resource)
    end)
    |> Enum.filter(fn identity ->
      Enum.all?(identity.keys, fn key ->
        Ash.Resource.Info.attribute(resource, key)
      end)
    end)
    |> Enum.map(fn identity ->
      %{identity | keys: Enum.sort(identity.keys)}
    end)
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&Map.take(&1, [:name, :keys]))
    |> Enum.map(fn identity ->
      Map.put(
        identity,
        :index_name,
        identity_index_names[identity.name] ||
          "#{AshPostgres.table(resource)}_#{identity.name}_index"
      )
    end)
    |> Enum.map(&Map.put(&1, :base_filter, AshPostgres.base_filter_sql(resource)))
  end

  @uuid_functions [&Ash.UUID.generate/0, &Ecto.UUID.generate/0]

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
  defp default(%{default: value}, _), do: EctoMigrationDefault.to_default(value)

  defp snapshot_to_binary(snapshot) do
    snapshot
    |> Map.update!(:attributes, fn attributes ->
      Enum.map(attributes, fn attribute ->
        %{attribute | type: sanitize_type(attribute.type, attribute[:size])}
      end)
    end)
    |> Jason.encode!(pretty: true)
  end

  defp sanitize_type({:array, type}, size) do
    ["array", sanitize_type(type, size)]
  end

  defp sanitize_type(:varchar, size) when not is_nil(size) do
    ["varchar", size]
  end

  defp sanitize_type(:binary, size) when not is_nil(size) do
    ["binary", size]
  end

  defp sanitize_type(type, _) do
    type
  end

  defp load_snapshot(json) do
    json
    |> Jason.decode!(keys: :atoms!)
    |> sanitize_snapshot()
  end

  defp sanitize_snapshot(snapshot) do
    snapshot
    |> Map.put_new(:has_create_action, true)
    |> Map.put_new(:schema, nil)
    |> Map.update!(:identities, fn identities ->
      Enum.map(identities, &load_identity(&1, snapshot.table))
    end)
    |> Map.update!(:attributes, fn attributes ->
      Enum.map(attributes, fn attribute ->
        attribute = load_attribute(attribute, snapshot.table)

        if is_map(Map.get(attribute, :references)) do
          %{
            attribute
            | references: rewrite(attribute.references, :ignore, :ignore?)
          }
        else
          attribute
        end
      end)
    end)
    |> Map.put_new(:custom_indexes, [])
    |> Map.update!(:custom_indexes, &load_custom_indexes/1)
    |> Map.put_new(:check_constraints, [])
    |> Map.update!(:check_constraints, &load_check_constraints/1)
    |> Map.update!(:repo, &String.to_atom/1)
    |> Map.put_new(:multitenancy, %{
      attribute: nil,
      strategy: nil,
      global: nil
    })
    |> Map.update!(:multitenancy, &load_multitenancy/1)
    |> Map.put_new(:base_filter, nil)
  end

  defp load_check_constraints(constraints) do
    Enum.map(constraints, fn constraint ->
      Map.update!(constraint, :attribute, fn attribute ->
        attribute
        |> List.wrap()
        |> Enum.map(&String.to_atom/1)
      end)
    end)
  end

  defp load_custom_indexes(custom_indexes) do
    Enum.map(custom_indexes || [], fn custom_index ->
      custom_index
      |> Map.put_new(:fields, [])
      |> Map.put_new(:include, [])
    end)
  end

  defp load_multitenancy(multitenancy) do
    multitenancy
    |> Map.update!(:strategy, fn strategy -> strategy && String.to_atom(strategy) end)
    |> Map.update!(:attribute, fn attribute -> attribute && String.to_atom(attribute) end)
  end

  defp load_attribute(attribute, table) do
    type = load_type(attribute.type)

    {type, size} =
      case type do
        {:varchar, size} ->
          {:varchar, size}

        {:binary, size} ->
          {:binary, size}

        other ->
          {other, nil}
      end

    attribute =
      if Map.has_key?(attribute, :name) do
        Map.put(attribute, :source, String.to_atom(attribute.name))
      else
        Map.update!(attribute, :source, &String.to_atom/1)
      end

    attribute
    |> Map.put(:type, type)
    |> Map.put(:size, size)
    |> Map.put_new(:default, "nil")
    |> Map.update!(:default, &(&1 || "nil"))
    |> Map.update!(:references, fn
      nil ->
        nil

      references ->
        references
        |> Map.delete(:ignore)
        |> rewrite(:ignore?, :ignore)
        |> Map.update!(:destination_field, &String.to_atom/1)
        |> Map.put_new(:schema, nil)
        |> Map.put_new(:destination_field_default, "nil")
        |> Map.put_new(:destination_field_generated, false)
        |> Map.put_new(:on_delete, nil)
        |> Map.put_new(:on_update, nil)
        |> Map.update!(:on_delete, &(&1 && String.to_atom(&1)))
        |> Map.update!(:on_update, &(&1 && String.to_atom(&1)))
        |> Map.put(
          :name,
          Map.get(references, :name) || "#{table}_#{attribute.source}_fkey"
        )
        |> Map.put_new(:multitenancy, %{
          attribute: nil,
          strategy: nil,
          global: nil
        })
        |> Map.update!(:multitenancy, &load_multitenancy/1)
        |> sanitize_name(table)
    end)
  end

  defp rewrite(map, key, to) do
    if Map.has_key?(map, key) do
      map
      |> Map.put(to, Map.get(map, key))
      |> Map.delete(key)
    else
      map
    end
  end

  defp sanitize_name(reference, table) do
    if String.starts_with?(reference.name, "_") do
      Map.put(reference, :name, "#{table}#{reference.name}")
    else
      reference
    end
  end

  defp load_type(["array", type]) do
    {:array, load_type(type)}
  end

  defp load_type(["varchar", size]) do
    {:varchar, size}
  end

  defp load_type(["binary", size]) do
    {:binary, size}
  end

  defp load_type(type) do
    String.to_atom(type)
  end

  defp load_identity(identity, table) do
    identity
    |> Map.update!(:name, &String.to_atom/1)
    |> Map.update!(:keys, fn keys ->
      keys
      |> Enum.map(&String.to_atom/1)
      |> Enum.sort()
    end)
    |> add_index_name(table)
    |> Map.put_new(:base_filter, nil)
  end

  defp add_index_name(%{name: name} = index, table) do
    Map.put_new(index, :index_name, "#{table}_#{name}_unique_index")
  end
end
