defmodule AshPostgres.ResourceGenerator.Spec do
  @moduledoc false
  require Logger

  defstruct [
    :attributes,
    :table_name,
    :repo,
    :resource,
    :schema,
    check_constraints: [],
    foreign_keys: [],
    indexes: [],
    identities: [],
    relationships: []
  ]

  defmodule Attribute do
    @moduledoc false
    defstruct [
      :name,
      :type,
      :attr_type,
      :default,
      :migration_default,
      :size,
      :source,
      generated?: false,
      primary_key?: false,
      sensitive?: false,
      allow_nil?: true
    ]
  end

  defmodule ForeignKey do
    @moduledoc false
    defstruct [
      :constraint_name,
      :match_type,
      :column,
      :references,
      :destination_field,
      :on_delete,
      :on_update,
      :match_with
    ]
  end

  defmodule Index do
    @moduledoc false
    defstruct [
      :name,
      :columns,
      :unique?,
      :nulls_distinct,
      :where_clause,
      :using,
      :include,
      :identity_name
    ]
  end

  defmodule CheckConstraint do
    @moduledoc false
    defstruct [:name, :column, :expression]
  end

  defmodule Relationship do
    @moduledoc false
    defstruct [
      :name,
      :type,
      :destination,
      :match_with,
      :source,
      :source_attribute,
      :constraint_name,
      :destination_attribute,
      :allow_nil?,
      :foreign_key
    ]
  end

  def tables(repo, opts \\ []) do
    {:ok, result, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        repo
        |> table_specs(opts)
        |> Enum.group_by(&Enum.take(&1, 2), fn [_, _, field, type, default, size, allow_nil?] ->
          name = Macro.underscore(field)

          %Attribute{
            name: name,
            source: field,
            type: type,
            migration_default: default,
            size: size,
            allow_nil?: allow_nil?
          }
        end)
        |> Enum.map(fn {[table_name, table_schema], attributes} ->
          attributes = build_attributes(attributes, table_name, table_schema, repo, opts)

          %__MODULE__{
            table_name: table_name,
            schema: table_schema,
            repo: repo,
            attributes: attributes
          }
        end)
        |> Enum.map(fn spec ->
          spec
          |> add_foreign_keys()
          |> add_indexes()
          |> add_check_constraints()
        end)
      end)

    result
  end

  defp add_foreign_keys(spec) do
    %Postgrex.Result{rows: fkey_rows} =
      spec.repo.query!(
        """
        SELECT
            tc.constraint_name,
            rc.match_option AS match_type,
            rc.update_rule AS on_update,
            rc.delete_rule AS on_delete,
            array_agg(DISTINCT kcu.column_name) AS referencing_columns,
            array_agg(DISTINCT ccu.column_name) AS referenced_columns,
            ccu.table_name AS foreign_table_name
        FROM
            information_schema.table_constraints AS tc
            JOIN information_schema.key_column_usage AS kcu
              ON tc.constraint_name = kcu.constraint_name
              AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage AS ccu
              ON ccu.constraint_name = tc.constraint_name
              AND ccu.table_schema = tc.table_schema
            JOIN information_schema.referential_constraints AS rc
              ON tc.constraint_name = rc.constraint_name
              AND tc.table_schema = rc.constraint_schema
        WHERE
            tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_name = $1
            AND tc.table_schema = $2
        GROUP BY
            tc.constraint_name,
            ccu.table_name,
            rc.match_option,
            rc.update_rule,
            rc.delete_rule;
        """,
        [spec.table_name, spec.schema],
        log: false
      )

    %{
      spec
      | foreign_keys:
          Enum.map(
            fkey_rows,
            fn [
                 constraint_name,
                 match_type,
                 on_update,
                 on_delete,
                 referencing_columns,
                 referenced_columns,
                 destination
               ] ->
              {[column_name], match_with_source} =
                Enum.split(referencing_columns, 1)

              {[destination_field], match_with_destination} =
                Enum.split(referenced_columns, 1)

              %ForeignKey{
                constraint_name: constraint_name,
                column: column_name,
                references: destination,
                destination_field: destination_field,
                on_delete: on_delete,
                on_update: on_update,
                match_type: match_type,
                match_with: Enum.zip(match_with_source, match_with_destination)
              }
            end
          )
    }
  end

  defp add_check_constraints(spec) do
    %Postgrex.Result{rows: check_constraint_rows} =
      spec.repo.query!(
        """
        SELECT
            conname AS constraint_name,
            pg_get_constraintdef(oid) AS constraint_definition
        FROM
            pg_constraint
        WHERE
            contype = 'c'
            AND conrelid::regclass::text = $1
        """,
        [spec.table_name],
        log: false
      )

    attribute = Enum.find(spec.attributes, & &1.primary_key?) || Enum.at(spec.attributes, 0)

    spec
    |> Map.put(
      :check_constraints,
      Enum.flat_map(check_constraint_rows, fn
        [name, "CHECK " <> expr] ->
          [
            %CheckConstraint{
              name: name,
              column: attribute.source,
              expression: expr
            }
          ]

        _ ->
          []
      end)
    )
  end

  defp add_indexes(spec) do
    %Postgrex.Result{rows: index_rows} =
      if Version.match?(spec.repo.min_pg_version(), ">= 15.0.0") do
        spec.repo.query!(
          """
          SELECT
              i.relname AS index_name,
              ix.indisunique AS is_unique,
              NOT(ix.indnullsnotdistinct) AS nulls_distinct,
              pg_get_expr(ix.indpred, ix.indrelid) AS where_clause,
              am.amname AS using_method,
              idx.indexdef
          FROM
              pg_index ix
          JOIN
              pg_class i ON ix.indexrelid = i.oid
          JOIN
              pg_class t ON ix.indrelid = t.oid
          JOIN
              pg_am am ON i.relam = am.oid
          LEFT JOIN
              pg_constraint c ON c.conindid = ix.indexrelid AND c.contype = 'p'
          JOIN
              pg_indexes idx ON idx.indexname = i.relname AND idx.schemaname = 'public' -- Adjust schema name if necessary
          JOIN information_schema.tables ta
              ON ta.table_name = t.relname
          WHERE
              t.relname = $1
              AND ta.table_schema = $2
              AND c.conindid IS NULL
          GROUP BY
              i.relname, ix.indisunique, ix.indnullsnotdistinct, pg_get_expr(ix.indpred, ix.indrelid), am.amname, idx.indexdef;
          """,
          [spec.table_name, spec.schema],
          log: false
        )
      else
        spec.repo.query!(
          """
          SELECT
              i.relname AS index_name,
              ix.indisunique AS is_unique,
              TRUE AS nulls_distinct,
              pg_get_expr(ix.indpred, ix.indrelid) AS where_clause,
              am.amname AS using_method,
              idx.indexdef
          FROM
              pg_index ix
          JOIN
              pg_class i ON ix.indexrelid = i.oid
          JOIN
              pg_class t ON ix.indrelid = t.oid
          JOIN
              pg_am am ON i.relam = am.oid
          LEFT JOIN
              pg_constraint c ON c.conindid = ix.indexrelid AND c.contype = 'p'
          JOIN
              pg_indexes idx ON idx.indexname = i.relname AND idx.schemaname = 'public' -- Adjust schema name if necessary
          JOIN information_schema.tables ta
              ON ta.table_name = t.relname
          WHERE
              t.relname = $1
              AND ta.table_schema = $2
              AND c.conindid IS NULL
          GROUP BY
              i.relname, ix.indisunique, pg_get_expr(ix.indpred, ix.indrelid), am.amname, idx.indexdef;
          """,
          [spec.table_name, spec.schema],
          log: false
        )
      end

    %{
      spec
      | indexes:
          index_rows
          |> Enum.flat_map(fn [
                                index_name,
                                is_unique,
                                nulls_distinct,
                                where_clause,
                                using,
                                index_def
                              ] ->
            index_name = String.slice(index_name, 0..63)

            case parse_columns_from_index_def(index_def, using) do
              {:ok, columns} ->
                include =
                  case String.split(index_def, "INCLUDE ") do
                    [_, included_cols] ->
                      try do
                        parse_columns(included_cols)
                      catch
                        :error ->
                          Logger.warning(
                            "Failed to parse includs from index definition: #{index_def}"
                          )

                          nil
                      end

                    _ ->
                      nil
                  end

                identity_name =
                  index_name
                  |> String.trim_leading(spec.table_name <> "_")
                  |> String.trim_leading("unique_")
                  |> String.replace("_unique_", "_")
                  |> String.trim_trailing("_index")
                  |> String.replace("_index_", "_")

                [
                  %Index{
                    name: index_name,
                    identity_name: identity_name,
                    columns: Enum.uniq(columns),
                    unique?: is_unique,
                    include: include,
                    using: using,
                    nulls_distinct: nulls_distinct,
                    where_clause: where_clause
                  }
                ]

              :error ->
                Logger.warning("Failed to parse index definition: #{index_def}")
                []
            end
          end)
    }
  end

  # CREATE INDEX users_lower_email_idx ON public.users USING btree (lower((email)::text))
  # CREATE INDEX unique_email_com3 ON public.users USING btree (email, id) WHERE (email ~~ '%.com'::citext)
  defp parse_columns_from_index_def(string, using) do
    string
    |> String.trim_leading("CREATE ")
    |> String.trim_leading("UNIQUE ")
    |> String.trim_leading("INDEX ")
    |> String.replace(~r/^[a-zA-Z0-9_\.]+\s/, "")
    |> String.trim_leading("ON ")
    |> String.replace(~r/^[\S]+/, "")
    |> String.trim_leading()
    |> String.trim_leading("USING #{using} ")
    |> do_parse_columns()
    |> then(&{:ok, &1})
  catch
    :error -> :error
  end

  def parse_columns(char) do
    do_parse_columns(char)
  end

  defp do_parse_columns(char, state \\ [], field \\ "", acc \\ [])

  defp do_parse_columns("(" <> rest, [], field, acc) do
    do_parse_columns(rest, [:outer], field, acc)
  end

  defp do_parse_columns(")" <> _rest, [:outer], field, acc) do
    if field == "" do
      Enum.reverse(acc)
    else
      Enum.reverse([field | acc])
    end
  end

  defp do_parse_columns("(" <> rest, [:outer], field, acc) do
    do_parse_columns(rest, [:in_paren, :in_field, :outer], field, acc)
  end

  defp do_parse_columns(", " <> rest, [:in_field, :outer], field, acc) do
    do_parse_columns(rest, [:in_field, :outer], "", [field | acc])
  end

  defp do_parse_columns(<<str::binary-size(1)>> <> rest, [:outer], field, acc) do
    do_parse_columns(rest, [:in_field, :outer], field <> str, acc)
  end

  defp do_parse_columns("''" <> rest, [:in_quote | stack], field, acc) do
    do_parse_columns(rest, [:in_quote | stack], field <> "'", acc)
  end

  defp do_parse_columns("'" <> rest, [:in_quote | stack], field, acc) do
    do_parse_columns(rest, stack, field <> "'", acc)
  end

  defp do_parse_columns(<<str::binary-size(1)>> <> rest, [:in_quote | stack], field, acc) do
    do_parse_columns(rest, [:in_quote | stack], field <> str, acc)
  end

  defp do_parse_columns("'" <> rest, stack, field, acc) do
    do_parse_columns(rest, [:in_quote | stack], field <> "'", acc)
  end

  defp do_parse_columns("(" <> rest, stack, field, acc) do
    do_parse_columns(rest, [:in_paren | stack], field <> "(", acc)
  end

  defp do_parse_columns(")" <> rest, [:in_paren | stack], field, acc) do
    do_parse_columns(rest, stack, field <> ")", acc)
  end

  defp do_parse_columns("), " <> rest, [:in_field | stack], field, acc) do
    do_parse_columns(rest, [:in_field | stack], "", [field | acc])
  end

  defp do_parse_columns(")" <> _rest, [:in_field | _stack], field, acc) do
    Enum.reverse([field | acc])
  end

  defp do_parse_columns(<<str::binary-size(1)>> <> rest, [:in_paren | stack], field, acc) do
    do_parse_columns(rest, [:in_paren | stack], field <> str, acc)
  end

  defp do_parse_columns(<<str::binary-size(1)>> <> rest, [:outer], field, acc) do
    do_parse_columns(rest, [:in_field, :outer], field <> str, acc)
  end

  defp do_parse_columns(<<str::binary-size(1)>> <> rest, [:in_field | stack], field, acc) do
    do_parse_columns(rest, [:in_field | stack], field <> str, acc)
  end

  defp do_parse_columns(", " <> rest, [:in_field | stack], field, acc) do
    do_parse_columns(rest, stack, "", [field | acc])
  end

  defp do_parse_columns(")" <> _rest, [:outer], field, acc) do
    Enum.reverse([field | acc])
  end

  defp do_parse_columns("", [:in_field | _stack], field, acc) do
    Enum.reverse([field | acc])
  end

  defp do_parse_columns("", [:outer], field, acc) do
    if field == "" do
      Enum.reverse(acc)
    else
      Enum.reverse([field | acc])
    end
  end

  defp do_parse_columns(other, stack, field, acc) do
    raise "Unexpected character: #{inspect(other)} at #{inspect(stack)} with #{inspect(field)} - #{inspect(acc)}"
  end

  defp build_attributes(attributes, table_name, schema, repo, opts) do
    attributes
    |> set_primary_key(table_name, schema, repo)
    |> set_sensitive()
    |> set_types(opts)
    |> set_defaults_and_generated()
  end

  # sobelow_skip ["DOS.StringToAtom"]
  defp set_defaults_and_generated(attributes) do
    Enum.map(attributes, fn attribute ->
      attribute =
        if attribute.migration_default do
          %{attribute | generated?: true}
        else
          attribute
        end

      case attribute do
        %{migration_default: nil} ->
          attribute

        %{migration_default: "CURRENT_TIMESTAMP"} ->
          %{attribute | default: &DateTime.utc_now/0}

        %{migration_default: "now()"} ->
          %{attribute | default: &DateTime.utc_now/0}

        %{migration_default: "(now() AT TIME ZONE 'utc'::text)"} ->
          %{attribute | default: &DateTime.utc_now/0}

        %{migration_default: "gen_random_uuid()"} ->
          %{attribute | default: &Ash.UUID.generate/0}

        %{migration_default: "uuid_generate_v4()"} ->
          %{attribute | default: &Ash.UUID.generate/0}

        %{attr_type: :integer, migration_default: value} ->
          case Integer.parse(value) do
            {value, ""} ->
              %{attribute | default: value}

            _ ->
              attribute
          end

        %{attr_type: :decimal, migration_default: value} ->
          case Decimal.parse(value) do
            {value, ""} ->
              %{attribute | default: Decimal.new(value)}

            _ ->
              attribute
          end

        %{attr_type: :map, migration_default: value} ->
          case Jason.decode(String.trim_trailing(value, "::json")) do
            {:ok, value} ->
              %{attribute | default: value}

            _ ->
              attribute
          end

        %{attr_type: type, migration_default: "'" <> value}
        when type in [:string, :ci_string, :atom] ->
          case String.trim_trailing(value, "'::text") do
            ^value ->
              attribute

            trimmed ->
              # This is very likely too naive
              attribute = %{attribute | default: String.replace(trimmed, "''", "'")}

              if type == :atom do
                %{attribute | default: String.to_atom(attribute.default)}
              else
                attribute
              end
          end

        _ ->
          attribute
      end
    end)
  end

  def add_relationships(specs, resources, opts) do
    specs
    |> Enum.group_by(& &1.repo)
    |> Enum.flat_map(fn {repo, specs} ->
      do_add_relationships(
        specs,
        Enum.flat_map(resources, fn resource ->
          if AshPostgres.DataLayer.Info.repo(resource) == repo do
            [{resource, AshPostgres.DataLayer.Info.table(resource)}]
          else
            []
          end
        end),
        opts
      )
    end)
  end

  defp do_add_relationships(specs, resources, opts) do
    specs =
      Enum.map(specs, fn spec ->
        belongs_to_relationships =
          Enum.flat_map(
            spec.foreign_keys,
            fn %ForeignKey{
                 constraint_name: constraint_name,
                 column: column_name,
                 references: references,
                 destination_field: destination_field,
                 match_with: match_with
               } ->
              case find_destination_and_field(
                     specs,
                     spec,
                     references,
                     destination_field,
                     resources,
                     match_with
                   ) do
                nil ->
                  []

                {destination, destination_attribute, match_with} ->
                  source_attr =
                    Enum.find(spec.attributes, fn attribute ->
                      attribute.source == column_name
                    end)

                  [
                    %Relationship{
                      type: :belongs_to,
                      name: Inflex.singularize(references),
                      source: spec.resource,
                      constraint_name: constraint_name,
                      match_with: match_with,
                      destination: destination,
                      source_attribute: source_attr.name,
                      allow_nil?: source_attr.allow_nil?,
                      destination_attribute: destination_attribute
                    }
                  ]
              end
            end
          )
          |> Enum.group_by(& &1.name)
          |> Enum.flat_map(fn
            {_name, [relationship]} ->
              [relationship]

            {name, relationships} ->
              name_all_relationships(:belongs_to, opts, spec, name, relationships)
          end)

        %{spec | relationships: belongs_to_relationships}
      end)

    Enum.map(specs, fn spec ->
      relationships_to_me =
        Enum.flat_map(specs, fn other_spec ->
          Enum.flat_map(other_spec.relationships, fn relationship ->
            if relationship.destination == spec.resource do
              [{other_spec.table_name, other_spec.resource, relationship}]
            else
              []
            end
          end)
        end)
        |> Enum.map(fn {table, resource, relationship} ->
          destination_field =
            Enum.find(spec.attributes, fn attribute ->
              attribute.name == relationship.destination_attribute
            end).source

          has_unique_index? =
            Enum.any?(spec.indexes, fn index ->
              index.unique? and is_nil(index.where_clause) and
                index.columns == [destination_field]
            end)

          {name, type} =
            if has_unique_index? do
              if Inflex.pluralize(table) == table do
                {Inflex.singularize(table), :has_one}
              else
                {table, :has_one}
              end
            else
              if Inflex.pluralize(table) == table do
                {table, :has_many}
              else
                {Inflex.pluralize(table), :has_many}
              end
            end

          %Relationship{
            type: type,
            name: name,
            destination: resource,
            source: spec.resource,
            match_with:
              Enum.map(relationship.match_with, fn {source, dest} ->
                {dest, source}
              end),
            constraint_name: relationship.constraint_name,
            source_attribute: relationship.destination_attribute,
            destination_attribute: relationship.source_attribute
          }
        end)
        |> Enum.group_by(& &1.name)
        |> Enum.flat_map(fn
          {_name, [relationship]} ->
            [relationship]

          {name, relationships} ->
            name_all_relationships(:has, opts, spec, name, relationships)
        end)

      %{spec | relationships: spec.relationships ++ relationships_to_me}
    end)
  end

  defp name_all_relationships(type, opts, spec, name, relationships, acc \\ [])
  defp name_all_relationships(_type, _opts, _spec, _name, [], acc), do: acc

  defp name_all_relationships(type, opts, spec, name, [relationship | rest], acc) do
    label =
      case type do
        :belongs_to ->
          """
          Multiple foreign keys found from `#{inspect(spec.resource)}` to `#{inspect(relationship.destination)}` with the guessed name `#{name}`.

          Provide a relationship name for the one with the following info:

          Resource: `#{inspect(spec.resource)}`
          Relationship Type: :belongs_to
          Guessed Name: `:#{name}`
          Relationship Destination: `#{inspect(relationship.destination)}`
          Constraint Name: `#{inspect(relationship.constraint_name)}`.

          Leave empty to skip adding this relationship.

          Name:
          """
          |> String.trim_trailing()

        _ ->
          """
          Multiple foreign keys found from `#{inspect(relationship.source)}` to `#{inspect(spec.resource)}` with the guessed name `#{name}`.

          Provide a relationship name for the one with the following info:

          Resource: `#{inspect(relationship.source)}`
          Relationship Type: :#{relationship.type}
          Guessed Name: `:#{name}`
          Relationship Destination: `#{inspect(spec.resource)}`
          Constraint Name: `#{inspect(relationship.constraint_name)}`.

          Leave empty to skip adding this relationship.

          Name:
          """
          |> String.trim_trailing()
      end

    Owl.IO.input(label: label)
    |> String.trim()
    # common typo
    |> String.trim_leading(":")
    |> case do
      "" ->
        name_all_relationships(type, opts, spec, name, rest, acc)

      new_name ->
        name_all_relationships(type, opts, spec, name, rest, [
          %{relationship | name: new_name} | acc
        ])
    end
  end

  defp find_destination_and_field(
         specs,
         spec,
         destination,
         destination_field,
         resources,
         match_with
       ) do
    case Enum.find(specs, fn other_spec ->
           other_spec.table_name == destination
         end) do
      nil ->
        case Enum.find(resources, fn {_resource, table} ->
               table == destination
             end) do
          nil ->
            nil

          {resource, _table} ->
            # this is cheating. We should be making sure the app is compiled
            # before our task is composed or pulling from source code
            attributes =
              resource
              |> Ash.Resource.Info.attributes()

            case Enum.reduce_while(match_with, {:ok, []}, fn {source, dest}, {:ok, acc} ->
                   with source_attr when not is_nil(source_attr) <-
                          Enum.find(spec.attributes, &(&1.source == source)),
                        dest_attr when not is_nil(dest_attr) <-
                          Enum.find(attributes, &(to_string(&1.source) == dest)) do
                     {:cont, {:ok, acc ++ [{source_attr.name, to_string(dest_attr.name)}]}}
                   else
                     _ ->
                       {:halt, :error}
                   end
                 end) do
              {:ok, match_with} ->
                Enum.find_value(attributes, fn attribute ->
                  if to_string(attribute.source) == destination_field do
                    {resource, to_string(attribute.name), match_with}
                  end
                end)

              _ ->
                nil
            end
        end

      %__MODULE__{} = other_spec ->
        case Enum.reduce_while(match_with, {:ok, []}, fn {source, dest}, {:ok, acc} ->
               with source_attr when not is_nil(source_attr) <-
                      Enum.find(spec.attributes, &(&1.source == source)),
                    dest_attr when not is_nil(dest_attr) <-
                      Enum.find(other_spec.attributes, &(&1.source == dest)) do
                 {:cont, {:ok, acc ++ [{source_attr.name, dest_attr.name}]}}
               else
                 _ ->
                   {:halt, :error}
               end
             end) do
          {:ok, match_with} ->
            other_spec.attributes
            |> Enum.find_value(fn %Attribute{} = attr ->
              if attr.source == destination_field do
                {other_spec.resource, attr.name, match_with}
              end
            end)

          _ ->
            nil
        end
    end
  end

  def set_types(attributes, opts) do
    attributes
    |> Enum.map(fn attribute ->
      case Process.get({:type_cache, attribute.type}) do
        nil ->
          case type(attribute.type) do
            {:ok, type} ->
              %{attribute | attr_type: type}

            :error ->
              get_type(attribute, opts)
          end

        type ->
          %{attribute | attr_type: type}
      end
    end)
  end

  # sobelow_skip ["RCE.CodeModule", "DOS.StringToAtom"]
  defp get_type(attribute, opts) do
    result =
      if opts[:yes?] do
        "skip"
      else
        Mix.shell().prompt("""
        Unknown type: #{attribute.type}. What should we use as the type?

        Provide the value as literal source code that should be placed into the
        generated file, i.e

           - :string
           - MyApp.Types.CustomType
           - {:array, :string}

        Use `skip` to skip ignore this attribute.
        """)
      end

    case result do
      skip when skip in ["skip", "skip\n"] ->
        attribute

      new_type ->
        case String.trim(new_type) do
          ":" <> type ->
            new_type = String.to_atom(type)
            Process.put({:type_cache, attribute.type}, new_type)
            %{attribute | attr_type: new_type}

          type ->
            try do
              Code.eval_string(type)
              Process.put({:type_cache, attribute.type}, new_type)
              %{attribute | attr_type: new_type}
            rescue
              e ->
                IO.puts(Exception.format(:error, e, __STACKTRACE__))

                get_type(attribute, opts)
            end
        end
    end
  end

  defp type("ARRAY of " <> rest) do
    case type(rest) do
      {:ok, type} -> {:ok, {:array, type}}
      :error -> :error
    end
  end

  defp type("bigint"), do: {:ok, :integer}
  defp type("bigserial"), do: {:ok, :integer}
  defp type("boolean"), do: {:ok, :boolean}
  defp type("bytea"), do: {:ok, :binary}
  defp type("varchar"), do: {:ok, :string}
  defp type("character varying"), do: {:ok, :string}
  defp type("date"), do: {:ok, :date}
  defp type("double precision"), do: {:ok, :decimal}
  defp type("int"), do: {:ok, :integer}
  defp type("integer"), do: {:ok, :integer}
  defp type("json"), do: {:ok, :map}
  defp type("jsonb"), do: {:ok, :map}
  defp type("numeric"), do: {:ok, :decimal}
  defp type("decimal"), do: {:ok, :decimal}
  defp type("smallint"), do: {:ok, :integer}
  defp type("smallserial"), do: {:ok, :ineger}
  defp type("serial"), do: {:ok, :integer}
  defp type("text"), do: {:ok, :string}
  defp type("time"), do: {:ok, :time}
  defp type("time without time zone"), do: {:ok, :time}
  defp type("time with time zone"), do: {:ok, :time}
  defp type("timestamp"), do: {:ok, :utc_datetime_usec}
  defp type("timestamp without time zone"), do: {:ok, :utc_datetime_usec}
  defp type("timestamp with time zone"), do: {:ok, :utc_datetime_usec}
  defp type("tsquery"), do: {:ok, AshPostgres.Tsquery}
  defp type("tsvector"), do: {:ok, AshPostgres.Tsvector}
  defp type("uuid"), do: {:ok, :uuid}
  defp type("citext"), do: {:ok, :ci_string}
  defp type("ltree"), do: {:ok, AshPostgres.Ltree}
  defp type(_), do: :error

  defp set_sensitive(attributes) do
    Enum.map(attributes, fn attribute ->
      %{
        attribute
        | sensitive?: AshPostgres.ResourceGenerator.SensitiveData.sensitive?(attribute.name)
      }
    end)
  end

  defp set_primary_key(attributes, table_name, schema, repo) do
    %Postgrex.Result{rows: pkey_rows} =
      repo.query!(
        """
        SELECT c.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage AS ccu USING (constraint_schema, constraint_name)
        JOIN information_schema.columns AS c ON c.table_schema = tc.constraint_schema
          AND tc.table_name = c.table_name AND ccu.column_name = c.column_name
        WHERE constraint_type = 'PRIMARY KEY' and tc.table_name = $1 AND tc.table_schema = $2;
        """,
        [table_name, schema],
        log: false
      )

    Enum.map(attributes, fn %Attribute{name: name} = attribute ->
      %{attribute | primary_key?: [name] in pkey_rows}
    end)
  end

  defp table_specs(repo, opts) do
    Enum.flat_map(opts[:tables] || ["public."], fn table ->
      {schema, table} =
        case String.split(table, ".") do
          [schema, table] ->
            {schema, table}

          [table] ->
            {"public", table}
        end

      %{rows: rows} =
        if table == "" do
          repo.query!(
            """
              SELECT
                t.table_name,
                t.table_schema,
                c.column_name,
                CASE WHEN c.data_type = 'ARRAY' THEN
                  repeat('ARRAY of ', a.attndims) || REPLACE(c.udt_name, '_', '')
                WHEN c.data_type = 'USER-DEFINED' THEN
                  c.udt_name
                ELSE
                  c.data_type
                END as data_type,
                c.column_default,
                c.character_maximum_length,
                c.is_nullable = 'YES'
              FROM
                  information_schema.tables t
              JOIN
                  information_schema.columns c
                  ON t.table_name = c.table_name
              JOIN pg_attribute a
                  ON a.attrelid = (
                      SELECT c.oid
                      FROM pg_class c
                      JOIN pg_namespace n ON c.relnamespace = n.oid
                      WHERE c.relname = t.table_name
                        AND n.nspname = t.table_schema
                        AND c.relkind = 'r'
                    )
                  AND a.attname = c.column_name
                  AND a.attnum > 0
              WHERE
                  t.table_name NOT LIKE 'pg_%'
                  AND t.table_name NOT LIKE '_pg_%'
                  AND t.table_schema = $1
              ORDER BY
                  t.table_name,
                  c.ordinal_position;
            """,
            [schema],
            log: false
          )
        else
          repo.query!(
            """
            SELECT
              t.table_name,
              t.table_schema,
              c.column_name,
              CASE WHEN c.data_type = 'ARRAY' THEN
                repeat('ARRAY of ', a.attndims) || REPLACE(c.udt_name, '_', '')
              WHEN c.data_type = 'USER-DEFINED' THEN
                c.udt_name
              ELSE
                c.data_type
              END as data_type,
              c.column_default,
              c.character_maximum_length,
              c.is_nullable = 'YES'
            FROM
                information_schema.tables t
            JOIN
                information_schema.columns c
                ON t.table_name = c.table_name
            JOIN pg_attribute a
                ON a.attrelid = (
                    SELECT c.oid
                    FROM pg_class c
                    JOIN pg_namespace n ON c.relnamespace = n.oid
                    WHERE c.relname = t.table_name
                      AND n.nspname = t.table_schema
                      AND c.relkind = 'r'
                  )
                AND a.attname = c.column_name
                AND a.attnum > 0
            WHERE
                t.table_schema = $1
                AND t.table_name = $2
            ORDER BY
                t.table_name,
                c.ordinal_position;
            """,
            [schema, table],
            log: false
          )
        end

      rows
    end)
  end
end
