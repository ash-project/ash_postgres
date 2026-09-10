# SPDX-FileCopyrightText: 2024 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Merge do
  @moduledoc false
  # Builds and executes PostgreSQL `MERGE` statements, used to implement `update_many`: many
  # heterogeneous updates in a single statement, each row of the `USING` source updating the
  # target row it matches. Both `MERGE ... RETURNING` and `merge_action()` require PostgreSQL 17,
  # so callers must gate on the server version.
  #
  # Upserts deliberately do not use `MERGE` (see `AshPostgres.Upsert`): it evaluates its `ON`
  # condition against a snapshot and does not arbitrate concurrent inserts of the same key, so
  # two concurrent upserts would both take `WHEN NOT MATCHED` and the loser would fail with a
  # unique violation. `INSERT ... ON CONFLICT` instead waits for the concurrent insert and then
  # runs the update.
  #
  # Ecto has no `MERGE` query type, so the statement text is assembled here. To avoid
  # re-implementing SQL generation, each piece is still produced by Ecto:
  #
  #   * the `USING` source is rendered by `Ecto.Query.values/2`, which handles type casting
  #     and parameter dumping
  #   * the `SET` clause and the `ON`/`WHEN` conditions are rendered from ordinary Ecto
  #     queries via `Ecto.Adapters.SQL.to_sql/4`, passing a `:counter` offset so the `$n`
  #     parameter placeholders of each piece line up when concatenated
  #
  # Ecto names the source in its rendered SQL positionally (e.g. `p0`). Rather than rewrite
  # those aliases, the target alias is read back out of the rendered `UPDATE ... AS <alias>`
  # and reused verbatim in the `MERGE INTO ... AS <alias>` header.
  #
  # The incoming row (the `USING` source) is aliased `AS EXCLUDED`, matching the name Postgres
  # gives it in `INSERT ... ON CONFLICT`. As a result, upsert expressions written either with
  # `upsert_conflict(:field)` or as a raw `fragment("EXCLUDED.col")` render and behave the same
  # whether the upsert runs through `MERGE` or `ON CONFLICT`.
  #
  # This module lives in ash_postgres because PostgreSQL is the only AshSql-backed database with
  # a `MERGE` statement (SQLite and MySQL have none). It relies only on the generic AshSql
  # machinery (bindings, atomics, expression rendering, `parameterized_type`) plus the `MERGE`
  # syntax and `merge_action()`, so it could be moved into ash_sql if another MERGE-capable
  # backend is ever added.

  import Ecto.Query, only: [from: 1]

  @source_alias "EXCLUDED"

  @doc """
  Executes a `MERGE` statement.

  Options:

    * `:resource` (required) - the Ash resource, used for column/type resolution and loading
    * `:table` (required) - the target table name
    * `:prefix` - the schema/prefix for the target table
    * `:entries` (required) - a list of attribute maps for the `USING (VALUES ...)` source
    * `:source_fields` - attribute names that must exist on the source in addition to the entry
      columns (e.g. match keys or calculation-key dependencies referenced via `EXCLUDED`); any not
      set by the entries are supplied as NULL
    * `:extra_source_columns` - synthetic (non-attribute) columns to add to the source, each
      `%{name: atom, type: ecto_type, values: [value_per_entry]}` (e.g. per-row present? flags for
      `update_many`). Exposed on `EXCLUDED`.
    * `:on_query` (required) - an `Ecto.Query` (`select: 1`, `where: <pred>`) whose WHERE is the
      full `ON` condition (per-key matching plus base_filter)
    * `:set_query` - an `Ecto.Query` carrying `update: [set: ...]` (no `where`); rendered into
      `WHEN MATCHED THEN UPDATE SET ...`. When absent/`:do_nothing`, `WHEN MATCHED` is omitted.
    * `:when_matched_condition_query` - optional `Ecto.Query` (`select: 1`, `where: <cond>`) whose
      WHERE becomes `WHEN MATCHED AND (<cond>)` (may reference `EXCLUDED`)
    * `:returning` - `true`, a list of fields, or `false`/`nil`
    * `:report_action?` - when true, append `merge_action()` and tag returned records with
      `:upsert_action` (`:update`) metadata

  Source rows that match no target row are ignored (`WHEN NOT MATCHED THEN DO NOTHING`).

  Returns `{count, records | nil}`.
  """
  def merge_all(repo, opts) do
    resource = Keyword.fetch!(opts, :resource)
    entries = Keyword.fetch!(opts, :entries)

    case entries do
      [] ->
        if opts[:returning], do: {0, []}, else: {0, nil}

      entries ->
        do_merge(repo, resource, entries, opts)
    end
  end

  defp do_merge(repo, resource, entries, opts) do
    table = Keyword.fetch!(opts, :table)
    prefix = opts[:prefix]

    # 1. USING (VALUES ...) AS EXCLUDED(cols) -- rendered, dumped, and cast by Ecto.
    {values_sql, values_params} =
      build_values_source(
        repo,
        resource,
        entries,
        opts[:source_fields] || [],
        opts[:extra_source_columns] || []
      )

    counter = length(values_params)

    # 2. ON <predicate> -- key matching + base_filter, rendered upstream.
    {on_predicate_sql, on_predicate_params, counter, target_alias_from_on} =
      render_optional_where(repo, Keyword.fetch!(opts, :on_query), counter)

    on_predicate_sql || raise(ArgumentError, "MERGE requires an ON condition")

    # 3. WHEN MATCHED [AND <cond>] THEN UPDATE SET <set>  (cond params precede set params)
    {when_matched_cond_sql, when_matched_cond_params, counter, target_alias_from_cond} =
      render_optional_where(repo, opts[:when_matched_condition_query], counter)

    {when_matched_sql, set_params, target_alias_from_set} =
      build_when_matched(repo, opts[:set_query], when_matched_cond_sql, counter)

    target_alias =
      pick_target_alias([
        target_alias_from_set,
        target_alias_from_cond,
        target_alias_from_on
      ])

    on_sql = [" ON ", on_predicate_sql]
    not_matched_sql = " WHEN NOT MATCHED THEN DO NOTHING"
    {returning_sql, returning_fields} = build_returning(opts, resource, target_alias)

    sql =
      IO.iodata_to_binary([
        "MERGE INTO ",
        quote_table(prefix, table),
        " AS ",
        target_alias,
        " USING (",
        values_sql,
        ") AS ",
        @source_alias,
        on_sql,
        when_matched_sql,
        not_matched_sql,
        returning_sql
      ])

    params = values_params ++ on_predicate_params ++ when_matched_cond_params ++ set_params

    result = repo.query!(sql, params)

    # Postgrex does not parse the `MERGE <n>` command tag, so `num_rows` is reported as 0.
    # When we requested RETURNING, the affected count is the number of returned rows.
    count = if is_list(result.rows), do: length(result.rows), else: result.num_rows

    {count,
     load_returned_rows(repo, resource, result.rows, returning_fields, %{
       source: table,
       prefix: prefix
     })}
  end

  defp build_values_source(repo, resource, entries, extra_fields, extra_columns) do
    entry_fields = entries |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

    # The source is referenced as `EXCLUDED` in the ON/SET/condition clauses. Beyond the entry
    # columns it must also expose any attribute referenced there but not set by these entries
    # (e.g. a match key with no provided value, or an attribute a calculation key depends on);
    # those are supplied as NULL.
    source_fields = Enum.uniq(entry_fields ++ extra_fields)

    attr_cols = source_columns(resource, source_fields)

    # Synthetic, non-attribute columns (e.g. per-row "is this column present?" flags for
    # update_many), exposed on `EXCLUDED` for the SET clause.
    types =
      attr_cols
      |> Map.new(fn {_field, source_col, type} -> {source_col, type} end)
      |> Map.merge(Map.new(extra_columns, fn %{name: name, type: type} -> {name, type} end))

    rows =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} ->
        attr_values =
          Map.new(attr_cols, fn {field, source_col, _type} ->
            {source_col, Map.get(entry, field)}
          end)

        synthetic_values =
          Map.new(extra_columns, fn %{name: name, values: values} ->
            {name, Enum.at(values, index)}
          end)

        Map.merge(attr_values, synthetic_values)
      end)

    {values_sql, values_params} =
      Ecto.Adapters.SQL.to_sql(:all, repo, from(v in values(rows, types)), counter: 0)

    {values_sql, values_params}
  end

  defp source_columns(resource, fields) do
    Enum.map(fields, fn field ->
      {field, db_column(resource, field), column_type(resource, field)}
    end)
  end

  # The Ecto type used to cast/dump a column of the source, resolved from the Ash field (which
  # may be an attribute, calculation, or aggregate). A configured `storage_type` wins; otherwise
  # the field's `{type, constraints}` are run through `parameterized_type/2` as elsewhere.
  defp column_type(resource, field) do
    AshPostgres.SqlImplementation.storage_type(resource, field) ||
      case field_type_and_constraints(resource, field) do
        {type, constraints} ->
          AshPostgres.SqlImplementation.parameterized_type(type, constraints || []) || type

        nil ->
          resource.__schema__(:type, field) ||
            raise ArgumentError,
                  "Cannot build MERGE source: #{inspect(field)} is not a field of #{inspect(resource)}"
      end
  end

  defp field_type_and_constraints(resource, field) do
    case Ash.Resource.Info.field(resource, field) do
      %Ash.Resource.Attribute{type: type, constraints: constraints} ->
        {type, constraints}

      %Ash.Resource.Calculation{type: type, constraints: constraints} ->
        {type, constraints}

      %Ash.Resource.Aggregate{} = aggregate ->
        aggregate_type_and_constraints(resource, aggregate)

      _ ->
        nil
    end
  end

  # Mirrors how aggregates are typed elsewhere: prefer an explicit type, otherwise derive it from
  # the aggregate kind and the type of the aggregated field.
  defp aggregate_type_and_constraints(_resource, %{type: type, constraints: constraints})
       when not is_nil(type),
       do: {type, constraints}

  defp aggregate_type_and_constraints(resource, aggregate) do
    {field_type, field_constraints} =
      case aggregate.field do
        nil ->
          {nil, nil}

        field ->
          related = Ash.Resource.Info.related(resource, aggregate.relationship_path)

          case Ash.Resource.Info.field(related, field) do
            %{type: type, constraints: constraints} -> {type, constraints}
            _ -> {nil, nil}
          end
      end

    case Ash.Query.Aggregate.kind_to_type(aggregate.kind, field_type, field_constraints) do
      {:ok, type, constraints} -> {type, constraints}
      _ -> {aggregate.type, aggregate.constraints || []}
    end
  end

  # The database column for a field, as Ecto knows it. This is the name used in the rendered
  # VALUES header, in `EXCLUDED.<col>`/`<target_alias>.<col>` references, and as the
  # `repo.load/2` key (which maps by source column, not field name).
  @doc false
  def db_column(resource, field) do
    resource.__schema__(:field_source, field) || field
  end

  defp build_when_matched(_repo, nil, _cond_sql, _counter), do: {"", [], nil}

  defp build_when_matched(_repo, :do_nothing, _cond_sql, _counter),
    do: {" WHEN MATCHED THEN DO NOTHING", [], nil}

  defp build_when_matched(repo, %Ecto.Query{} = set_query, cond_sql, counter) do
    {sql, params} = Ecto.Adapters.SQL.to_sql(:update_all, repo, set_query, counter: counter)
    {target_alias, set_clause} = extract_set_clause(sql)

    cond_part = if cond_sql, do: [" AND ", cond_sql], else: []
    {[" WHEN MATCHED", cond_part, " THEN UPDATE SET ", set_clause], params, target_alias}
  end

  defp build_returning(opts, resource, target_alias) do
    case opts[:returning] do
      nil -> {"", nil}
      false -> {"", nil}
      fields -> build_returning_fields(fields, resource, target_alias, opts[:report_action?])
    end
  end

  defp build_returning_fields(fields, resource, target_alias, report_action?) do
    fields =
      case fields do
        true -> Ash.Resource.Info.attributes(resource) |> Enum.map(& &1.name)
        fields when is_list(fields) -> fields
      end

    # Use the Ecto source column for both the SQL projection and the `repo.load/2` key.
    sources = Enum.map(fields, &db_column(resource, &1))

    col_sql =
      Enum.map_join(sources, ", ", fn source_col ->
        "#{target_alias}.#{quote_name(source_col)}"
      end)

    action_sql = if report_action?, do: ", merge_action()", else: ""

    {" RETURNING " <> col_sql <> action_sql,
     %{sources: sources, action: if(report_action?, do: :merge_action)}}
  end

  @doc false
  # Loads the rows of a `RETURNING` clause into resource records.
  #
  # `returning_fields` is `nil` (nothing was returned) or `%{sources: [column], action: mode}`:
  # each row holds one value per source column followed, when `mode` is set, by a trailing
  # action value that becomes `:upsert_action` metadata. `mode` is `:merge_action` for the
  # `INSERT`/`UPDATE`/`DELETE` strings of `merge_action()`, or `:from_inserted_flag` for the
  # boolean of `(xmax = 0)` in an `INSERT ... ON CONFLICT` (`true` -> `:insert`, `false` ->
  # `:update`).
  def load_returned_rows(_repo, _resource, _rows, nil, _meta), do: nil

  def load_returned_rows(repo, resource, rows, %{sources: sources, action: mode}, meta) do
    Enum.map(rows, fn row ->
      {source_values, action} =
        if mode do
          {action_value, values} = List.pop_at(row, length(sources))
          {Enum.zip(sources, values), upsert_action(mode, action_value)}
        else
          {Enum.zip(sources, row), nil}
        end

      record =
        repo.load(resource, Map.new(source_values))
        |> Map.put(:__meta__, %Ecto.Schema.Metadata{
          state: :loaded,
          source: meta.source,
          prefix: meta[:prefix],
          schema: resource
        })

      if action do
        Ash.Resource.put_metadata(record, :upsert_action, action)
      else
        record
      end
    end)
  end

  defp upsert_action(:merge_action, "INSERT"), do: :insert
  defp upsert_action(:merge_action, "UPDATE"), do: :update
  defp upsert_action(:merge_action, "DELETE"), do: :delete
  defp upsert_action(:merge_action, _), do: nil
  defp upsert_action(:from_inserted_flag, true), do: :insert
  defp upsert_action(:from_inserted_flag, false), do: :update
  defp upsert_action(:from_inserted_flag, _), do: nil

  # Deterministically pull clauses out of rendered SQL (no alias rewriting).
  # `UPDATE "table" AS <alias> SET <set>` -> {alias, set}
  defp extract_set_clause(update_sql) do
    {before_set, after_set} = split_sql_keyword!(update_sql, "SET")

    set_clause =
      after_set
      |> trim_sql_keyword("WHERE")
      |> trim_sql_keyword("RETURNING")
      |> String.trim()

    {read_trailing_alias(before_set), set_clause}
  end

  # `SELECT ... FROM "table" AS <alias> WHERE <pred>` -> {alias, "(pred)"}; nil query -> all-nil
  defp render_optional_where(_repo, nil, counter), do: {nil, [], counter, nil}

  defp render_optional_where(repo, %Ecto.Query{} = query, counter) do
    {sql, params} = Ecto.Adapters.SQL.to_sql(:all, repo, query, counter: counter)
    {before_where, after_where} = split_sql_keyword!(sql, "WHERE")

    pred =
      after_where
      |> trim_sql_keyword("GROUP BY")
      |> trim_sql_keyword("ORDER BY")
      |> trim_sql_keyword("LIMIT")
      |> trim_sql_keyword("OFFSET")
      |> String.trim()

    {pred, params, counter + length(params), read_trailing_alias(before_where)}
  end

  # The alias Ecto emits for the (single) source. In `... "table" AS p0 ...` it is the last
  # whitespace-delimited token before the split keyword.
  @doc false
  def read_trailing_alias(before_keyword) do
    before_keyword
    |> String.trim()
    |> String.split()
    |> List.last()
  end

  defp pick_target_alias(candidates) do
    case Enum.uniq(Enum.reject(candidates, &is_nil/1)) do
      [] ->
        raise ArgumentError,
              "MERGE requires at least a SET clause or a condition to derive the target alias"

      [alias] ->
        alias

      aliases ->
        raise ArgumentError,
              "Rendered MERGE clauses disagree on the target alias: #{inspect(aliases)}. " <>
                "This usually means a clause referenced a joined source, which MERGE cannot express."
    end
  end

  # Scans for a top-level SQL keyword, skipping quoted strings and parens (not a regex).
  @doc false
  def split_sql_keyword!(sql, keyword) do
    case split_sql_keyword(sql, keyword) do
      nil -> raise ArgumentError, "Expected #{keyword} in rendered SQL: #{inspect(sql)}"
      split -> split
    end
  end

  defp split_sql_keyword(sql, keyword) do
    pattern = " #{keyword} "

    case find_top_level(sql, pattern) do
      nil ->
        nil

      pos ->
        {String.slice(sql, 0, pos), String.slice(sql, (pos + String.length(pattern))..-1//1)}
    end
  end

  defp trim_sql_keyword(sql, keyword) do
    case split_sql_keyword(sql, keyword) do
      {before, _} -> before
      nil -> sql
    end
  end

  # Finds `pattern` at the top level, ignoring matches inside single quotes,
  # double-quoted identifiers, and parentheses.
  defp find_top_level(sql, pattern), do: find_top_level(sql, pattern, 0, 0, :normal)

  defp find_top_level(sql, pattern, pos, depth, state) do
    remaining = String.slice(sql, pos..-1//1)

    if remaining == "" do
      nil
    else
      case state do
        :normal ->
          cond do
            depth == 0 && String.starts_with?(remaining, pattern) ->
              pos

            String.starts_with?(remaining, "'") ->
              find_top_level(sql, pattern, pos + 1, depth, :single_quote)

            String.starts_with?(remaining, "\"") ->
              find_top_level(sql, pattern, pos + 1, depth, :double_quote)

            String.starts_with?(remaining, "(") ->
              find_top_level(sql, pattern, pos + 1, depth + 1, :normal)

            String.starts_with?(remaining, ")") && depth > 0 ->
              find_top_level(sql, pattern, pos + 1, depth - 1, :normal)

            true ->
              find_top_level(sql, pattern, pos + 1, depth, :normal)
          end

        :single_quote ->
          cond do
            String.starts_with?(remaining, "''") ->
              find_top_level(sql, pattern, pos + 2, depth, :single_quote)

            String.starts_with?(remaining, "'") ->
              find_top_level(sql, pattern, pos + 1, depth, :normal)

            true ->
              find_top_level(sql, pattern, pos + 1, depth, :single_quote)
          end

        :double_quote ->
          cond do
            String.starts_with?(remaining, "\"\"") ->
              find_top_level(sql, pattern, pos + 2, depth, :double_quote)

            String.starts_with?(remaining, "\"") ->
              find_top_level(sql, pattern, pos + 1, depth, :normal)

            true ->
              find_top_level(sql, pattern, pos + 1, depth, :double_quote)
          end
      end
    end
  end

  @doc false
  def quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))

  def quote_name(name) when is_binary(name) do
    if String.contains?(name, "\"") do
      raise ArgumentError, "bad field/table name #{inspect(name)}"
    end

    <<?", name::binary, ?">>
  end

  @doc false
  def quote_table(nil, table), do: quote_name(table)
  def quote_table(prefix, table), do: "#{quote_name(prefix)}.#{quote_name(table)}"
end
