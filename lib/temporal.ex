# SPDX-FileCopyrightText: 2024 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Temporal do
  @moduledoc false
  # Emits `UPDATE/DELETE ... FOR PORTION OF <valid_at> FROM $1 TO NULL ...`
  # for temporal resources. Postgres applies the change only to the slice of each
  # matched row from `as_of` onward, truncating the prior row at `as_of` (its
  # before-portion is preserved as a new row). A temporal write is always
  # `[as_of, ∞)`, so `TO` is always `NULL` (the open/unbounded end) and `FROM` is
  # the changeset's `as_of`. `TO NULL` (not `TO 'infinity'`) is essential: a current
  # row's stored upper is unbounded (`NULL`), and `'infinity'` is a real value that
  # an unbounded range *contains* — splitting `TO 'infinity'` would leave a literal
  # `'infinity'` upper (which Postgrex can't decode) plus a junk `[infinity, )` row.
  #
  # Ecto has no `FOR PORTION OF`, and PG requires the clause BETWEEN the table and
  # the `AS` alias (`UPDATE t AS a FOR PORTION OF ...` is a syntax error). So we
  # render the statement with Ecto (`to_sql`, with the bound as `$1` via a counter
  # offset), splice the clause in after the table, and run it via `repo.query!`.
  # Mirrors the approach in `AshPostgres.Merge`.

  @doc """
  Atomic temporal upsert for one or more changesets.

  Postgres can't `INSERT ... ON CONFLICT` against a `WITHOUT OVERLAPS` exclusion PK,
  and `MERGE`'s matched action can't split a period. So we emit one data-modifying CTE
  per `as_of`, driven by a `VALUES` source of the changesets:

      WITH src(<cols>) AS (VALUES (...), (...)),
        upd AS (
          UPDATE t FOR PORTION OF <valid_at> FROM $as_of TO NULL
          SET <col> = src.<col>, ... FROM src
          WHERE t.<keys> = src.<keys> AND t.<valid_at> @> $as_of   -- period AT as_of
          RETURNING t.*
        ),
        ins AS (
          INSERT INTO t (<cols>, <valid_at>)
          SELECT src.<cols>, <bounded range> FROM src
          WHERE NOT EXISTS (SELECT 1 FROM upd WHERE upd.<keys> = src.<keys>)
          RETURNING *
        )
      SELECT * FROM upd UNION ALL SELECT * FROM ins

  Per changeset: match the period valid AT `as_of` and split it via `FOR PORTION OF`
  (future periods, which don't contain `as_of`, are untouched); if none, insert a new
  period bounded to the next one — or unbounded above when there is no later period.

  All changesets sharing an `as_of` run in one statement (the `FOR PORTION OF` bound is a
  single parameter — it can't be a per-row column). Changesets with differing `as_of`s are
  grouped and run as one statement each, inside a transaction. Returns `{:ok, records}`.
  """
  def upsert_all(repo, resource, changesets, upsert_keys, upsert_fields \\ nil) do
    now = DateTime.utc_now()

    groups =
      Enum.group_by(changesets, fn changeset ->
        case changeset.as_of do
          nil -> now
          :now -> now
          as_of -> as_of
        end
      end)

    run = fn ->
      Enum.flat_map(groups, fn {as_of, group} ->
        upsert_group(repo, resource, group, upsert_keys, upsert_fields, as_of)
      end)
    end

    records =
      if map_size(groups) > 1 do
        {:ok, records} = repo.transaction(run)
        records
      else
        run.()
      end

    {:ok, records}
  end

  defp upsert_group(repo, resource, changesets, upsert_keys, upsert_fields, as_of) do
    attribute = Ash.Resource.Info.temporal_attribute(resource)
    prefix = get_in(hd(changesets).context, [:data_layer, :schema])
    qtable = quote_table(prefix, AshPostgres.DataLayer.Info.table(resource))
    tname = quote_name(AshPostgres.DataLayer.Info.table(resource))
    qattr = quote_name(attribute)
    adapter = repo.__adapter__()

    # The columns to write — every changeset attribute in the group except the temporal
    # range, which we build from `as_of`.
    insert_cols =
      changesets
      |> Enum.flat_map(fn cs -> Map.keys(Map.drop(cs.attributes, [attribute])) end)
      |> Enum.uniq()

    # On a match, set the configured `upsert_fields` (or all written columns), minus the
    # keys and the range itself.
    set_fields =
      (upsert_fields || insert_cols)
      |> Enum.filter(&(&1 in insert_cols))
      |> Kernel.--(upsert_keys)
      |> Kernel.--([attribute])

    col_types = column_types(repo, qtable)
    qsrc = fn field -> quote_name(source_col(resource, field)) end
    col_count = length(insert_cols)

    # `VALUES` rows + their params. `$1` is `as_of`; row i, column j is `$(2 + i*c + j)`.
    # The first row carries `::type` casts so Postgres knows each `src` column's type.
    {rows_sql, row_params} =
      changesets
      |> Enum.with_index()
      |> Enum.map(fn {changeset, ri} ->
        insert_cols
        |> Enum.with_index()
        |> Enum.map(fn {field, ci} ->
          n = 2 + ri * col_count + ci

          {:ok, dumped} =
            Ecto.Type.adapter_dump(
              adapter,
              resource.__schema__(:type, field),
              Map.get(changeset.attributes, field)
            )

          placeholder =
            if ri == 0 do
              "$#{n}::#{Map.fetch!(col_types, to_string(source_col(resource, field)))}"
            else
              "$#{n}"
            end

          {placeholder, dumped}
        end)
        |> Enum.unzip()
        |> then(fn {phs, vals} -> {"(" <> Enum.join(phs, ", ") <> ")", vals} end)
      end)
      |> Enum.unzip()

    params = [as_of | List.flatten(row_params)]

    src_clause =
      "src(#{Enum.map_join(insert_cols, ", ", qsrc)}) AS (VALUES #{Enum.join(rows_sql, ", ")})"

    key_match = fn left ->
      Enum.map_join(upsert_keys, " AND ", fn k -> "#{left}.#{qsrc.(k)} = src.#{qsrc.(k)}" end)
    end

    has_update? = set_fields != []

    upd_cte =
      if has_update? do
        set_sql = Enum.map_join(set_fields, ", ", fn f -> "#{qsrc.(f)} = src.#{qsrc.(f)}" end)

        "upd AS (UPDATE #{qtable} FOR PORTION OF #{qattr} FROM $1::timestamptz TO NULL " <>
          "SET #{set_sql} FROM src " <>
          "WHERE #{key_match.(tname)} AND #{tname}.#{qattr} @> $1::timestamptz RETURNING #{tname}.*)"
      end

    not_exists =
      if has_update? do
        "NOT EXISTS (SELECT 1 FROM upd WHERE #{key_match.("upd")})"
      else
        "NOT EXISTS (SELECT 1 FROM #{qtable} ex WHERE #{key_match.("ex")} " <>
          "AND ex.#{qattr} @> $1::timestamptz)"
      end

    # Bound the inserted range to this key's next period (gap-fill), else unbounded above
    # (NULL upper — the temporal "current" period; `'infinity'` can't be decoded).
    range_sql =
      "tstzrange($1::timestamptz, (SELECT min(lower(#{qattr})) FROM #{qtable} s2 " <>
        "WHERE #{key_match.("s2")} AND lower(#{qattr}) > $1::timestamptz))"

    insert_cols_sql = Enum.map_join(insert_cols ++ [attribute], ", ", qsrc)

    insert_select_sql =
      Enum.map_join(insert_cols, ", ", fn f -> "src.#{qsrc.(f)}" end) <> ", " <> range_sql

    ins_cte =
      "ins AS (INSERT INTO #{qtable} (#{insert_cols_sql}) " <>
        "SELECT #{insert_select_sql} FROM src WHERE #{not_exists} RETURNING *)"

    sql =
      if has_update? do
        "WITH #{src_clause}, #{upd_cte}, #{ins_cte} SELECT * FROM upd UNION ALL SELECT * FROM ins"
      else
        "WITH #{src_clause}, #{ins_cte} SELECT * FROM ins"
      end

    result = repo.query!(sql, params)

    repo
    |> load_rows(resource, result.columns, result.rows || [])
    |> tag_bulk_refs(changesets, upsert_keys)
  end

  # Ash's bulk action correlates each returned record back to its changeset via
  # `__metadata__.bulk_action_ref`. Our `UNION` returns rows out of input order, so we
  # re-attach the ref by matching each record's upsert-key values to its changeset.
  # (No-op for the single-record `upsert/4` path, whose changeset has no bulk context.)
  defp tag_bulk_refs(records, changesets, upsert_keys) do
    ref_by_identity =
      changesets
      |> Enum.flat_map(fn changeset ->
        case get_in(changeset.context, [:bulk_create, :ref]) do
          nil -> []
          ref -> [{Enum.map(upsert_keys, &Map.get(changeset.attributes, &1)), ref}]
        end
      end)
      |> Map.new()

    if ref_by_identity == %{} do
      records
    else
      Enum.map(records, fn record ->
        case Map.get(ref_by_identity, Enum.map(upsert_keys, &Map.get(record, &1))) do
          nil -> record
          ref -> Ash.Resource.put_metadata(record, :bulk_action_ref, ref)
        end
      end)
    end
  end

  # The Postgres type of each column (e.g. `"integer"`, `"tstzrange"`) so `VALUES` params
  # can be cast — otherwise they default to `text` and join/compare against typed columns.
  defp column_types(repo, qtable) do
    %{rows: rows} =
      repo.query!(
        "SELECT a.attname, format_type(a.atttypid, a.atttypmod) FROM pg_attribute a " <>
          "WHERE a.attrelid = $1::text::regclass AND a.attnum > 0 AND NOT a.attisdropped",
        [qtable]
      )

    Map.new(rows, fn [name, type] -> {name, type} end)
  end

  @doc "Run an UPDATE ... FOR PORTION OF. Returns `{count, loaded_records | nil}`."
  def update_all(repo, query, resource, as_of) do
    run(repo, :update_all, query, resource, as_of)
  end

  @doc "Run a DELETE ... FOR PORTION OF. Returns `{count, loaded_records | nil}`."
  def delete_all(repo, query, resource, as_of) do
    run(repo, :delete_all, query, resource, as_of)
  end

  defp run(repo, kind, query, resource, as_of) do
    attribute = Ash.Resource.Info.temporal_attribute(resource)
    returning? = not is_nil(query.select)

    # Render with the bound reserved as $1.
    {sql, params} =
      Ecto.Adapters.SQL.to_sql(kind, repo, Map.delete(query, :__ash_bindings__), counter: 1)

    sql = splice_for_portion_of(sql, kind, attribute)
    result = repo.query!(sql, [as_of | params])

    if returning? do
      rows = result.rows || []
      {length(rows), load_rows(repo, resource, result.columns, rows)}
    else
      {result.num_rows, nil}
    end
  end

  # Insert ` FOR PORTION OF "<attr>" FROM $1::timestamptz TO NULL` immediately
  # after the table name and before the ` AS <alias>` that Ecto emits. `TO NULL` is
  # the open/unbounded upper — see the moduledoc for why not `'infinity'`.
  defp splice_for_portion_of(sql, kind, attribute) do
    {head, rest} = split_on_set_or_where(sql, kind)
    alias_token = head |> String.trim() |> String.split() |> List.last()
    table_part = String.replace_suffix(head, " AS #{alias_token}", "")

    clause =
      " FOR PORTION OF " <>
        quote_name(attribute) <> " FROM $1::timestamptz TO NULL"

    table_part <> clause <> " AS " <> alias_token <> rest
  end

  # `head` is everything up to (and including the keyword we split on); `rest`
  # is the keyword + remainder. We keep the keyword on `rest`.
  defp split_on_set_or_where(sql, :update_all), do: split_keeping(sql, " SET ")

  defp split_on_set_or_where(sql, :delete_all) do
    case find_top_level(sql, " WHERE ") do
      nil -> split_keeping(sql, " RETURNING ")
      _ -> split_keeping(sql, " WHERE ")
    end
  end

  defp split_keeping(sql, keyword) do
    case find_top_level(sql, keyword) do
      nil ->
        raise ArgumentError, "Expected #{keyword} in rendered temporal SQL: #{inspect(sql)}"

      pos ->
        {String.slice(sql, 0, pos), String.slice(sql, pos..-1//1)}
    end
  end

  defp load_rows(repo, resource, columns, rows) do
    source = AshPostgres.DataLayer.Info.table(resource)
    keys = Enum.map(columns, &String.to_existing_atom/1)

    Enum.map(rows, fn row ->
      repo.load(resource, Map.new(Enum.zip(keys, row)))
      |> Map.put(:__meta__, %Ecto.Schema.Metadata{
        state: :loaded,
        source: source,
        schema: resource
      })
    end)
  end

  defp quote_table(nil, table), do: quote_name(table)
  defp quote_table(prefix, table), do: quote_name(prefix) <> "." <> quote_name(table)

  defp source_col(resource, field) do
    case Ash.Resource.Info.attribute(resource, field) do
      %{source: source} when not is_nil(source) -> source
      %{name: name} -> name
      _ -> field
    end
  end

  defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))

  defp quote_name(name) when is_binary(name) do
    if String.contains?(name, "\""), do: raise(ArgumentError, "bad column name #{inspect(name)}")
    <<?", name::binary, ?">>
  end

  # Top-level keyword search, ignoring quotes and parens (from AshPostgres.Merge).
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
end
