# SPDX-FileCopyrightText: 2024 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Upsert do
  @moduledoc false
  # Builds and executes `INSERT ... ON CONFLICT DO UPDATE ... RETURNING` statements, which is how
  # upserts are implemented.
  #
  # `INSERT ... ON CONFLICT` is the only PostgreSQL statement that arbitrates concurrent writers:
  # if two transactions insert the same key at the same time, the loser waits for the winner and
  # then takes the `DO UPDATE` branch instead of failing. `MERGE` (see `AshPostgres.Merge`) does
  # not do this, and raises a unique violation instead, which is why upserts do not use it even
  # on PostgreSQL 17+.
  #
  # The statement rendered here is exactly what `repo.insert_all/3` with `:on_conflict` renders:
  # the rows are dumped through the resource's Ecto schema, missing columns become `DEFAULT`, and
  # the `DO UPDATE SET ... WHERE ...` clause is rendered from an Ecto query. The reason to assemble
  # it by hand is the `RETURNING` list. Ecto can only return schema fields, and we want one extra
  # expression, `(xmax = 0)`, to report per row whether it was inserted or updated (surfaced as
  # `:upsert_action` metadata, matching what `MERGE ... RETURNING merge_action()` provides).
  #
  # Why `xmax = 0` tells inserts from updates: a row version written by an `INSERT` has no
  # deleter or locker, so its `xmax` is 0. When `ON CONFLICT` takes the `DO UPDATE` branch,
  # PostgreSQL first locks the conflicting row and then updates it, and the new row version
  # carries that lock forward, so its `xmax` is the current transaction id (never 0). This has
  # been the behavior since `ON CONFLICT` was introduced in 9.5 and is the standard way to tell
  # the two apart.
  #
  # The per-clause SQL is produced by Ecto (`Ecto.Adapters.SQL.to_sql/4` with a `:counter`
  # offset so `$n` placeholders line up when concatenated), and the generic splicing helpers are
  # shared with `AshPostgres.Merge`.

  import AshPostgres.Merge,
    only: [
      quote_name: 1,
      quote_table: 2,
      db_column: 2,
      split_sql_keyword!: 2,
      read_trailing_alias: 1,
      load_returned_rows: 5
    ]

  @doc """
  Executes an `INSERT ... ON CONFLICT DO UPDATE` statement.

  Options:

    * `:resource` (required) - the Ash resource, used for column/type resolution and loading
    * `:table` (required) - the target table name
    * `:prefix` - the schema/prefix for the target table
    * `:entries` (required) - a list of attribute maps to insert. Values may be `Ecto.Query`
      structs (atomic insert values), which are rendered as subqueries.
    * `:on_conflict` (required) - an `Ecto.Query` carrying `update: [set: ...]` and optionally a
      `where` (the upsert condition), rendered into `DO UPDATE SET ... [WHERE ...]`
    * `:conflict_target` (required) - a list of attribute names, or `{:unsafe_fragment, sql}`
    * `:returning` - `true`, a list of fields, or `false`/`nil`
    * `:query_opts` - options forwarded to `repo.query!/3` (e.g. `:timeout`, `:log`)

  Returns `{count, records | nil}`, the same shape as `repo.insert_all/3`.
  """
  def insert_all(repo, opts) do
    resource = Keyword.fetch!(opts, :resource)
    entries = Keyword.fetch!(opts, :entries)

    case entries do
      [] ->
        if opts[:returning], do: {0, []}, else: {0, nil}

      entries ->
        do_insert_all(repo, resource, entries, opts)
    end
  end

  defp do_insert_all(repo, resource, entries, opts) do
    table = Keyword.fetch!(opts, :table)
    prefix = opts[:prefix]

    # 1. (cols) VALUES ($1, $2, DEFAULT), ... -- values dumped through the resource's Ecto schema.
    {header, values_sql, values_params, counter} = build_values(repo, resource, entries)

    # 2. ON CONFLICT (<target>) DO UPDATE SET <set> [WHERE <cond>] -- rendered by Ecto from the
    #    on_conflict query, just as `repo.insert_all/3` does.
    {on_conflict_sql, on_conflict_params, target_alias} =
      build_on_conflict(
        repo,
        resource,
        Keyword.fetch!(opts, :on_conflict),
        Keyword.fetch!(opts, :conflict_target),
        prefix,
        counter
      )

    {returning_sql, returning_fields} = build_returning(opts[:returning], resource, target_alias)

    sql =
      IO.iodata_to_binary([
        "INSERT INTO ",
        quote_table(prefix, table),
        " AS ",
        target_alias,
        " (",
        Enum.map_join(header, ", ", &quote_name/1),
        ") VALUES ",
        values_sql,
        on_conflict_sql,
        returning_sql
      ])

    params = values_params ++ on_conflict_params

    query_opts =
      Keyword.merge(
        [source: table, cache_statement: "ash_postgres_upsert_#{table}"],
        opts[:query_opts] || []
      )

    result = repo.query!(sql, params, query_opts)

    count = if is_list(result.rows), do: length(result.rows), else: result.num_rows

    {count,
     load_returned_rows(repo, resource, result.rows, returning_fields, %{
       source: table,
       prefix: prefix
     })}
  end

  # Renders `(...), (...)` with one `$n` per provided value (dumped via the schema's Ecto types),
  # `DEFAULT` for columns an entry does not set, and `(SELECT ...)` for `Ecto.Query` values.
  # Mirrors `Ecto.Repo.Schema.insert_all/5`, so database defaults apply exactly as they would
  # through `repo.insert_all/3`.
  defp build_values(repo, resource, entries) do
    dumper = resource.__schema__(:dump)
    adapter = repo.__adapter__()

    fields = entries |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()

    columns =
      Enum.map(fields, fn field ->
        case dumper do
          %{^field => {source, type, writable}} when writable != :never ->
            {field, source, type}

          %{} ->
            raise ArgumentError,
                  "unknown field `#{inspect(field)}` in #{inspect(resource)} given to upsert. " <>
                    "Unwritable fields, such as virtual and read only fields, are not supported."
        end
      end)

    # `counter` is the number of parameters rendered so far, so the next placeholder is
    # `$counter+1` (the same convention `Ecto.Adapters.SQL.to_sql/4` uses for `:counter`).
    # `params` accumulates reversed groups of parameters; a group is a list so that array values
    # stay intact when the groups are concatenated.
    {rows_sql, {params, counter}} =
      Enum.map_reduce(entries, {[], 0}, fn entry, {params, counter} ->
        {cells, {params, counter}} =
          Enum.map_reduce(columns, {params, counter}, fn {field, _source, type},
                                                         {params, counter} ->
            case Map.fetch(entry, field) do
              :error ->
                {"DEFAULT", {params, counter}}

              {:ok, %Ecto.Query{} = query} ->
                {sql, query_params} =
                  Ecto.Adapters.SQL.to_sql(:all, repo, query, counter: counter)

                {["(", sql, ")"], {[query_params | params], counter + length(query_params)}}

              {:ok, value} ->
                {"$#{counter + 1}",
                 {[[dump!(adapter, resource, field, type, value)] | params], counter + 1}}
            end
          end)

        {["(", Enum.intersperse(cells, ","), ")"], {params, counter}}
      end)

    header = Enum.map(columns, fn {_field, source, _type} -> source end)
    params = params |> Enum.reverse() |> Enum.concat()

    {header, Enum.intersperse(rows_sql, ","), params, counter}
  end

  defp dump!(adapter, resource, field, type, value) do
    case Ecto.Type.adapter_dump(adapter, type, value) do
      {:ok, value} ->
        value

      :error ->
        raise Ecto.ChangeError,
              "value `#{inspect(value)}` for `#{inspect(resource)}.#{field}` " <>
                "in `upsert` does not match type #{Ecto.Type.format(type)}"
    end
  end

  # `UPDATE "table" AS <alias> SET <set> [WHERE <cond>]` -> ` ON CONFLICT <target> DO UPDATE SET
  # <set> [WHERE <cond>]`. The prefix is applied to the query as `repo.insert_all/3` does, so any
  # subqueries in the SET/WHERE expressions resolve against the same schema as the target table.
  defp build_on_conflict(repo, resource, %Ecto.Query{} = query, conflict_target, prefix, counter) do
    query = if prefix, do: %{query | prefix: prefix}, else: query

    {sql, params} = Ecto.Adapters.SQL.to_sql(:update_all, repo, query, counter: counter)
    {before_set, set_and_where} = split_sql_keyword!(sql, "SET")

    on_conflict_sql = [
      " ON CONFLICT ",
      render_conflict_target(resource, conflict_target),
      " DO UPDATE SET ",
      String.trim(set_and_where)
    ]

    {on_conflict_sql, params, read_trailing_alias(before_set)}
  end

  defp render_conflict_target(_resource, {:unsafe_fragment, fragment}), do: fragment

  defp render_conflict_target(resource, fields) when is_list(fields) do
    ["(", Enum.map_join(fields, ", ", &quote_name(db_column(resource, &1))), ")"]
  end

  defp build_returning(nil, _resource, _target_alias), do: {"", nil}
  defp build_returning(false, _resource, _target_alias), do: {"", nil}

  defp build_returning(fields, resource, target_alias) do
    fields =
      case fields do
        true -> resource.__schema__(:fields)
        fields when is_list(fields) -> fields
      end

    sources = Enum.map(fields, &db_column(resource, &1))

    col_sql = Enum.map_join(sources, ", ", &"#{target_alias}.#{quote_name(&1)}")

    {" RETURNING " <> col_sql <> ", (#{target_alias}.xmax = 0)",
     %{sources: sources, action: :from_inserted_flag}}
  end
end
