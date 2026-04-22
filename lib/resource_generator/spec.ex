# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ResourceGenerator.Spec do
  @moduledoc false
  require Logger

  defstruct [
    :attributes,
    :table_name,
    :repo,
    :resource,
    :schema,
    kind: :table,
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
      :foreign_key,
      :through,
      :source_attribute_on_join_resource,
      :destination_attribute_on_join_resource,
      :join_relationship,
      :referenced_table
    ]
  end

  def tables(repo, opts \\ []) do
    {:ok, result, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        rows = table_specs(repo, opts)

        relkinds =
          Enum.reduce(rows, %{}, fn [table_name, table_schema, _, _, _, _, _, relkind], acc ->
            Map.put_new(acc, {table_name, table_schema}, relkind_to_kind(relkind))
          end)

        rows
        |> Enum.group_by(
          &Enum.take(&1, 2),
          fn [_, _, field, type, default, size, allow_nil?, _relkind] ->
            name = Macro.underscore(field)

            %Attribute{
              name: name,
              source: field,
              type: type,
              migration_default: default,
              size: size,
              allow_nil?: allow_nil?
            }
          end
        )
        |> Enum.map(fn {[table_name, table_schema], attributes} ->
          kind = Map.get(relkinds, {table_name, table_schema}, :table)

          attributes = build_attributes(attributes, table_name, table_schema, repo, opts, kind)

          %__MODULE__{
            table_name: table_name,
            schema: table_schema,
            repo: repo,
            kind: kind,
            attributes: attributes
          }
        end)
        |> Enum.map(fn spec ->
          case spec.kind do
            :table ->
              spec
              |> add_foreign_keys()
              |> add_indexes()
              |> add_check_constraints()

            :materialized_view ->
              add_indexes(spec)

            :view ->
              spec
          end
        end)
        |> Enum.reject(fn spec ->
          spec.table_name in List.wrap(opts[:skip_tables])
        end)
      end)

    result
  end

  defp relkind_to_kind("r"), do: :table
  defp relkind_to_kind("v"), do: :view
  defp relkind_to_kind("m"), do: :materialized_view
  defp relkind_to_kind(_), do: :table

  defp qualified_table_name(%{schema: schema, table_name: table_name}) do
    "#{schema}.#{table_name}"
  end

  defp add_foreign_keys(spec) do
    qualified_table = qualified_table_name(spec)

    %Postgrex.Result{rows: fkey_rows} =
      spec.repo.query!(
        """
        -- This has to go via the pg_constraints table directly
        -- because the built in constraint view does not surface the table name
        -- and constraint names are only unique per table
        WITH constraints AS (SELECT conname                                       as constraint_name,
                                    ns.nspname::information_schema.sql_identifier AS table_schema,
                                    CASE pgc.confmatchtype
                                        WHEN 'f'::"char" THEN 'FULL'::text
                                        WHEN 'p'::"char" THEN 'PARTIAL'::text
                                        WHEN 's'::"char" THEN 'NONE'::text
                                        ELSE NULL::text
                                        END                                       AS match_option,
                                    CASE pgc.confupdtype
                                        WHEN 'c'::"char" THEN 'CASCADE'::text
                                        WHEN 'n'::"char" THEN 'SET NULL'::text
                                        WHEN 'd'::"char" THEN 'SET DEFAULT'::text
                                        WHEN 'r'::"char" THEN 'RESTRICT'::text
                                        WHEN 'a'::"char" THEN 'NO ACTION'::text
                                        ELSE NULL::text
                                        END                                       AS update_rule,
                                    CASE pgc.confdeltype
                                        WHEN 'c'::"char" THEN 'CASCADE'::text
                                        WHEN 'n'::"char" THEN 'SET NULL'::text
                                        WHEN 'd'::"char" THEN 'SET DEFAULT'::text
                                        WHEN 'r'::"char" THEN 'RESTRICT'::text
                                        WHEN 'a'::"char" THEN 'NO ACTION'::text
                                        ELSE NULL::text
                                        END                                       AS delete_rule
                            FROM pg_constraint AS pgc
                                      INNER JOIN pg_namespace AS ns ON pgc.connamespace = ns.oid
                            WHERE pgc.contype = 'f' -- Foreign key
                              AND pgc.conrelid = $1::text::regclass
                              AND ns.nspname = $2)
        SELECT constraints.constraint_name,
              constraints.match_option,
              constraints.update_rule,
              constraints.delete_rule,
              array_agg(DISTINCT kcu.column_name) AS referencing_columns,
              array_agg(DISTINCT ccu.column_name) AS referenced_columns,
              ccu.table_name                      AS foreign_table_name
        FROM information_schema.key_column_usage AS kcu
                JOIN constraints
                      ON constraints.constraint_name = kcu.constraint_name
                          AND constraints.table_schema = kcu.table_schema
                JOIN information_schema.constraint_column_usage AS ccu
                      ON ccu.constraint_name = constraints.constraint_name
                          AND ccu.table_schema = constraints.table_schema
        GROUP BY constraints.constraint_name,
                ccu.table_name,
                constraints.match_option,
                constraints.update_rule,
                constraints.delete_rule
        """,
        [qualified_table, spec.schema],
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
    qualified_table = qualified_table_name(spec)

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
        [qualified_table],
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
              pg_catalog.pg_namespace tn ON tn.oid = t.relnamespace
          JOIN
              pg_am am ON i.relam = am.oid
          LEFT JOIN
              pg_constraint c ON c.conindid = ix.indexrelid AND c.contype = 'p'
          JOIN
              pg_indexes idx ON idx.indexname = i.relname AND idx.schemaname = $2
          WHERE
              t.relname = $1
              AND tn.nspname = $2
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
              pg_catalog.pg_namespace tn ON tn.oid = t.relnamespace
          JOIN
              pg_am am ON i.relam = am.oid
          LEFT JOIN
              pg_constraint c ON c.conindid = ix.indexrelid AND c.contype = 'p'
          JOIN
              pg_indexes idx ON idx.indexname = i.relname AND idx.schemaname = $2
          WHERE
              t.relname = $1
              AND tn.nspname = $2
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
    |> String.replace(~r/^"?[a-zA-Z0-9_\.]+"?\s/, "")
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

  defp build_attributes(attributes, table_name, schema, repo, opts, kind) do
    attributes
    |> set_primary_key(table_name, schema, repo, kind)
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
          build_belongs_to_relationships(spec, specs, resources, opts)

        %{spec | relationships: belongs_to_relationships}
      end)

    Enum.map(specs, fn spec ->
      relationships_to_me =
        Enum.flat_map(specs, fn other_spec ->
          Enum.flat_map(other_spec.relationships, fn relationship ->
            if relationship.destination == spec.resource do
              [{other_spec.table_name, other_spec.resource, other_spec, relationship}]
            else
              []
            end
          end)
        end)
        |> Enum.flat_map(fn {table, resource, other_spec, relationship} ->
          reverse_rel = build_has_relationship(spec, table, resource, relationship)

          maybe_m2m =
            if !opts[:skip_many_to_many] do
              build_many_to_many_relationship(spec, other_spec, relationship, reverse_rel, specs)
            end

          [reverse_rel | List.wrap(maybe_m2m)]
        end)
        |> resolve_name_collisions(
          opts,
          spec,
          Enum.map(spec.attributes, & &1.name) ++ Enum.map(spec.relationships, & &1.name)
        )

      %{spec | relationships: spec.relationships ++ relationships_to_me}
    end)
  end

  defp build_belongs_to_relationships(spec, specs, resources, opts) do
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
                name: default_belongs_to_name(column_name, references),
                referenced_table: references,
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
    |> resolve_name_collisions(opts, spec, Enum.map(spec.attributes, & &1.name))
  end

  defp build_many_to_many_relationship(spec, other_spec, relationship, reverse_rel, specs) do
    with true <- join_table?(other_spec),
         other_fk when not is_nil(other_fk) <-
           Enum.find(other_spec.foreign_keys, &(&1.references != spec.table_name)),
         dest_spec when not is_nil(dest_spec) <-
           Enum.find(specs, &(&1.table_name == other_fk.references)) do
      %Relationship{
        type: :many_to_many,
        name: safe_pluralize(other_fk.references),
        source: spec.resource,
        destination: dest_spec.resource,
        through: other_spec.resource,
        referenced_table: other_fk.references,
        source_attribute: relationship.destination_attribute,
        destination_attribute: other_fk.destination_field,
        source_attribute_on_join_resource: relationship.source_attribute,
        destination_attribute_on_join_resource: other_fk.column,
        join_relationship: reverse_rel.name,
        match_with: []
      }
    else
      _ -> nil
    end
  end

  defp build_has_relationship(spec, table, resource, relationship) do
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
        {Igniter.Inflex.singularize(table), :has_one}
      else
        {safe_pluralize(table), :has_many}
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
  end

  defp safe_pluralize(table) do
    # handles edge cases when multiple pluralizations are possible like: "person" -> "people" -> "peoples"
    table
    |> Igniter.Inflex.singularize()
    |> Igniter.Inflex.pluralize()
  end

  defp join_table?(spec) do
    pk_cols =
      spec.attributes
      |> Enum.filter(& &1.primary_key?)
      |> Enum.map(& &1.source)

    fk_cols = Enum.map(spec.foreign_keys, & &1.column)

    fk_tables =
      spec.foreign_keys
      |> Enum.map(& &1.references)
      |> Enum.uniq()

    length(spec.foreign_keys) == 2 &&
      length(fk_tables) == 2 &&
      Enum.sort(pk_cols) == Enum.sort(fk_cols)
  end

  defp resolve_name_collisions(relationships, opts, spec, reserved_names) do
    resolved =
      relationships
      |> Enum.group_by(& &1.name)
      |> Enum.flat_map(fn {name, rels} ->
        if length(rels) > 1 or name in reserved_names do
          name_all_relationships(opts, spec, name, rels)
        else
          rels
        end
      end)

    if same_relationship_names?(relationships, resolved) do
      resolved
    else
      resolve_name_collisions(resolved, opts, spec, reserved_names)
    end
  end

  defp same_relationship_names?(a, b) do
    Enum.sort(Enum.map(a, & &1.name)) == Enum.sort(Enum.map(b, & &1.name))
  end

  defp name_all_relationships(opts, spec, name, relationships, acc \\ [])
  defp name_all_relationships(_opts, _spec, _name, [], acc), do: acc

  defp name_all_relationships(opts, spec, name, [%Relationship{} = relationship | rest], acc) do
    {info, suggestion} = relationship_conflict_info(spec, name, relationship)
    maybe_suggestion = if suggestion == name, do: nil, else: suggestion

    case choose_relationship_name(opts, name, maybe_suggestion, info) do
      :skip ->
        name_all_relationships(opts, spec, name, rest, acc)

      new_name ->
        name_all_relationships(opts, spec, name, rest, [
          %{relationship | name: new_name} | acc
        ])
    end
  end

  defp relationship_conflict_info(spec, name, %Relationship{type: :belongs_to} = relationship) do
    suggestion =
      build_alternative_name(relationship.source_attribute, relationship.referenced_table)

    info = """
    The guessed relationship name `:#{name}` on `#{inspect(spec.resource)}` conflicts with another name on this resource.

    Relationship info:
      Resource:                 #{inspect(spec.resource)}
      Relationship Type:        :belongs_to
      Guessed Name:             :#{name}
      Relationship Destination: #{inspect(relationship.destination)}
      Source Attribute (FK):    #{inspect(relationship.source_attribute)}
      Constraint Name:          #{inspect(relationship.constraint_name)}
    """

    {info, suggestion}
  end

  defp relationship_conflict_info(_spec, name, %Relationship{type: :many_to_many} = relationship) do
    suggestion =
      build_alternative_name(relationship.source_attribute_on_join_resource, name)

    info = """
    The guessed relationship name `:#{name}` on `#{inspect(relationship.source)}` conflicts with another name on this resource.

    Relationship info:
      Resource:                      #{inspect(relationship.source)}
      Relationship Type:             :many_to_many
      Guessed Name:                  :#{name}
      Relationship Destination:      #{inspect(relationship.destination)}
      Destination Attribute on Join: #{inspect(relationship.destination_attribute_on_join_resource)}
      Source Attribute on Join:      #{inspect(relationship.source_attribute_on_join_resource)}
      Join Resource (Through):       #{inspect(relationship.through)}
    """

    {info, suggestion}
  end

  defp relationship_conflict_info(_spec, name, %Relationship{} = relationship) do
    suggestion = build_alternative_name(relationship.destination_attribute, name)

    info = """
    The guessed relationship name `:#{name}` on `#{inspect(relationship.source)}` conflicts with another name on this resource.

    Relationship info:
      Resource:                   #{inspect(relationship.source)}
      Relationship Type:          :#{relationship.type}
      Guessed Name:               :#{name}
      Relationship Destination:   #{inspect(relationship.destination)}
      Destination Attribute (FK): #{inspect(relationship.destination_attribute)}
      Constraint Name:            #{inspect(relationship.constraint_name)}
    """

    {info, suggestion}
  end

  defp choose_relationship_name(opts, name, maybe_suggestion, info) do
    if opts[:yes] || opts[:skip_unknown] do
      maybe_suggestion || :skip
    else
      prompt_relationship_name(name, maybe_suggestion, info)
    end
  end

  defp prompt_relationship_name(name, maybe_suggestion, info) do
    Owl.IO.puts(info)

    options =
      [
        maybe_suggestion && {:suggest, "Use suggested name `:#{maybe_suggestion}`"},
        {:skip, "Skip this relationship"}
      ]
      |> Enum.reject(&is_nil/1)

    menu =
      options
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{_action, label}, idx} -> "  #{idx}. #{label}" end)

    prompt_label =
      "How would you like to resolve the conflict for `:#{name}`?\n" <>
        menu <> "\n  Or enter a custom name."

    Owl.IO.input(
      label: prompt_label,
      optional: true,
      cast: &parse_relationship_name_input(&1, options)
    )
    |> case do
      :suggest -> maybe_suggestion || :skip
      :skip -> :skip
      nil -> maybe_suggestion || :skip
      new_name -> new_name
    end
  end

  defp parse_relationship_name_input(nil, _options), do: {:ok, nil}

  defp parse_relationship_name_input(value, options) when is_binary(value) do
    # common typo
    trimmed = value |> String.trim() |> String.trim_leading(":")

    case Integer.parse(trimmed) do
      {idx, ""} when idx >= 1 ->
        case Enum.at(options, idx - 1) do
          {action, _label} -> {:ok, action}
          nil -> {:error, "please choose a listed option or enter a custom name"}
        end

      _ ->
        case trimmed do
          "" -> {:ok, nil}
          new_name -> {:ok, new_name}
        end
    end
  end

  defp build_alternative_name(attribute, name) do
    if String.ends_with?(attribute, "_id") do
      stripped =
        attribute
        |> String.replace("_id", "")
        |> Igniter.Inflex.singularize()

      if stripped == Igniter.Inflex.singularize(to_string(name)) do
        name
      else
        "#{stripped}_#{name}"
      end
    else
      name
    end
  end

  defp default_belongs_to_name(column_name, references) do
    if String.ends_with?(column_name, "_id") and String.length(column_name) > 3 do
      String.replace_suffix(column_name, "_id", "")
    else
      references
    end
    |> Igniter.Inflex.singularize()
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
    |> Enum.flat_map(fn attribute ->
      case Process.get({:type_cache, attribute.type}) do
        nil ->
          case type(attribute.type) do
            {:ok, type} ->
              [%{attribute | attr_type: type}]

            :error ->
              case get_type(attribute, opts) do
                :skip -> []
                {:ok, type} -> [%{attribute | attr_type: type}]
              end
          end

        type ->
          [%{attribute | attr_type: type}]
      end
    end)
  end

  # sobelow_skip ["RCE.CodeModule", "DOS.StringToAtom"]
  defp get_type(attribute, opts) do
    result =
      if opts[:yes] || opts[:skip_unknown] do
        "skip"
      else
        Mix.shell().prompt("""
        Unknown type: #{attribute.type}. What should we use as the type?

        Provide the value as literal source code that should be placed into the
        generated file, i.e

           - :string
           - MyApp.Types.CustomType
           - {:array, :string}

        Use `skip` to ignore this attribute.
        """)
      end

    case result do
      skip when skip in ["skip", "skip\n"] ->
        :skip

      new_type ->
        case String.trim(new_type) do
          ":" <> type ->
            new_type = String.to_atom(type)
            Process.put({:type_cache, attribute.type}, new_type)
            {:ok, new_type}

          type ->
            try do
              Process.put({:type_cache, attribute.type}, new_type)
              {:ok, type}
            rescue
              _e ->
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
  defp type("identity"), do: {:ok, :identity}
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
  defp type("smallserial"), do: {:ok, :integer}
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

  defp set_primary_key(attributes, _table_name, _schema, _repo, kind) when kind != :table do
    attributes
  end

  defp set_primary_key(attributes, table_name, schema, repo, _kind) do
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
    relkind_filter =
      if opts[:include_views] do
        "IN ('r', 'v', 'm')"
      else
        "= 'r'"
      end

    Enum.flat_map(opts[:tables] || ["public."], fn table ->
      {schema, table} =
        case String.split(table, ".") do
          [schema, table] ->
            {schema, table}

          [table] ->
            {"public", table}
        end

      {table_filter, params} =
        if table == "" do
          {"", [schema]}
        else
          {"AND c.relname = $2", [schema, table]}
        end

      %{rows: rows} =
        repo.query!(
          """
          SELECT
            c.relname AS table_name,
            n.nspname AS table_schema,
            a.attname AS column_name,
            CASE
              WHEN t.typcategory = 'A' THEN
                repeat('ARRAY of ', COALESCE(a.attndims, 1)) || REPLACE(et.typname, '_', '')
              WHEN t.typtype = 'e' THEN
                t.typname
              ELSE
                format_type(t.oid, NULL)
            END AS data_type,
            pg_get_expr(d.adbin, d.adrelid) AS column_default,
            CASE
              WHEN t.typname IN ('varchar', 'bpchar') AND a.atttypmod > 4 THEN a.atttypmod - 4
              ELSE NULL
            END AS character_maximum_length,
            NOT a.attnotnull AS is_nullable,
            c.relkind
          FROM pg_catalog.pg_class c
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
          JOIN pg_catalog.pg_type t ON t.oid = a.atttypid
          LEFT JOIN pg_catalog.pg_type et ON et.oid = t.typelem
          LEFT JOIN pg_catalog.pg_attrdef d
            ON d.adrelid = a.attrelid AND d.adnum = a.attnum
          WHERE c.relkind #{relkind_filter}
            AND n.nspname = $1
            AND a.attnum > 0
            AND NOT a.attisdropped
            AND c.relname NOT LIKE 'pg_%'
            AND c.relname NOT LIKE '_pg_%'
            #{table_filter}
          ORDER BY c.relname, a.attnum;
          """,
          params,
          log: false
        )

      rows
    end)
  end
end
