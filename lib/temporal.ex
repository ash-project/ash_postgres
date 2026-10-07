# SPDX-FileCopyrightText: 2024 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Temporal do
  @moduledoc false
  # Splits periods for temporal writes. A write changes only the slice of each matched
  # version that falls inside its *portion*: `[as_of, ∞)` for an instant, or the period
  # itself when `as_of` names one. The rest of the version is kept as it was, as one or
  # two *leftover* rows.
  #
  # That's SQL:2011's `UPDATE/DELETE ... FOR PORTION OF`, which Postgres doesn't have (it
  # was reverted from 19 before release, over the same READ COMMITTED lost updates handled
  # below). Once Postgres ships it natively, we'll use it. Until then we do it by hand, in
  # one statement, using PG18's `RETURNING old`:
  #
  #     WITH "__fpo" AS (
  #       UPDATE t AS s0 SET ..., valid_at = s0.valid_at * <portion>
  #       WHERE (...) AND (s0.valid_at && <portion>)
  #       RETURNING ..., old AS "__old"
  #     ), "__leftovers" AS (
  #       INSERT INTO t (<cols>, valid_at)
  #       SELECT (f."__old").<col>, ..., l.r
  #       FROM "__fpo" f, unnest(multirange((f."__old").valid_at) - multirange(<portion>)) l(r)
  #     )
  #     SELECT ... FROM "__fpo"
  #
  # A delete is the same, except it removes the whole version and the leftovers put back
  # what was outside the portion.
  #
  # The portion's upper is `NULL` (unbounded), never `'infinity'`. A current version's
  # stored upper is unbounded, and `'infinity'` is a real value that an unbounded range
  # *contains*, so splitting at it would leave a literal `'infinity'` upper (which
  # Postgrex can't decode) plus a junk `[infinity, )` row.
  #
  # Concurrency: under READ COMMITTED, two writes to one record can lose an update. The
  # second blocks on the version the first is splitting and rechecks it once the first
  # commits, but by then the version may no longer match (so it's skipped), and the
  # leftovers the first inserted are newer than the second's snapshot (so they're never
  # seen). This is what got `FOR PORTION OF` reverted.
  #
  # So each statement first locks the versions it's about to split, and compares them
  # with the versions its snapshot matched (see `gate_ctes/2`). Locking waits out any
  # concurrent write and then sees the version as that write left it, so if the two
  # differ, a concurrent write got in the way. The writes are gated on that, so the
  # statement writes nothing and we just run it again, with a snapshot that sees what the
  # other write committed. No savepoint needed: a savepoint per write would cost two round
  # trips and a subtransaction, and enough subtransactions in one transaction slow down
  # every snapshot on the server.
  #
  # When there's nothing to lock (an upsert of a record that doesn't exist yet, or into a
  # gap), the constraint behind the upsert keys catches a concurrent insert instead: the
  # `WITHOUT OVERLAPS` primary key, or the identity's exclusion constraint. Our insert waits
  # for the other one and then conflicts. It skips that key (`ON CONFLICT ON CONSTRAINT
  # <that constraint> DO NOTHING`) and we retry just the skipped keys.
  #
  # Under REPEATABLE READ and SERIALIZABLE, Postgres raises a serialization failure for
  # these cases itself.

  # How many times a write runs before giving up on getting past concurrent writes.
  @attempts 25

  @doc """
  Atomic temporal upsert for one or more changesets.

  Postgres can't `INSERT ... ON CONFLICT` against a `WITHOUT OVERLAPS` exclusion PK,
  and `MERGE`'s matched action can't split a period. So we emit one data-modifying CTE
  per `as_of`, driven by a `VALUES` source of the changesets:

      WITH src(<cols>) AS (VALUES (...), (...)),
        upd AS (
          UPDATE t SET <col> = src.<col>, ..., <valid_at> = t.<valid_at> * [as_of, ∞)
          FROM src
          WHERE t.<keys> = src.<keys> AND t.<valid_at> @> $as_of   -- period AT as_of
          AND NOT <conflict>                                       -- see `gate_ctes/2`
          RETURNING new AS "__new", old AS "__old"
        ),
        "__leftovers" AS (INSERT INTO t ... the part of each matched period before as_of),
        ins AS (
          INSERT INTO t (<cols>, <valid_at>)
          SELECT src.<cols>, <bounded range> FROM src
          WHERE NOT <conflict>
            AND NOT EXISTS (SELECT 1 FROM upd WHERE (upd."__new").<keys> = src.<keys>)
          ON CONFLICT ON CONSTRAINT <keys' constraint> DO NOTHING  -- lost a race: retried
          RETURNING ...
        )
      SELECT (upd."__new").* FROM upd UNION ALL SELECT * FROM ins

  Per changeset: match the period valid AT `as_of` and split it there (future periods,
  which don't contain `as_of`, are untouched); if none, insert a new period bounded to
  the next one — or unbounded above when there is no later period.

  All changesets sharing an `as_of` run in one statement (the split point is a single
  parameter — it can't be a per-row column). Changesets with differing `as_of`s are
  grouped and run as one statement each, inside a transaction. Returns `{:ok, records}`.
  """
  def upsert_all(repo, resource, changesets, upsert_keys, upsert_fields \\ nil, prefix \\ nil) do
    now = DateTime.utc_now()

    groups =
      Enum.group_by(changesets, fn changeset ->
        case changeset.as_of do
          nil -> now
          :now -> now
          as_of -> as_of
        end
      end)

    # The tenant's schema under context multitenancy, else the resource's `schema`
    prefix = prefix || get_in(hd(changesets).context, [:data_layer, :schema])
    qtable = quote_table(prefix, AshPostgres.DataLayer.Info.table(resource))
    col_types = column_types(repo, qtable)

    records =
      transaction(repo, fn ->
        Enum.flat_map(groups, fn {as_of, group} ->
          upsert_group(
            repo,
            resource,
            qtable,
            col_types,
            group,
            upsert_keys,
            upsert_fields,
            as_of
          )
        end)
      end)

    {:ok, records}
  end

  defp upsert_group(
         repo,
         resource,
         qtable,
         col_types,
         changesets,
         upsert_keys,
         upsert_fields,
         as_of,
         attempt \\ 1
       ) do
    attribute = Ash.Resource.Info.temporal_attribute(resource)
    tname = quote_name(AshPostgres.DataLayer.Info.table(resource))
    qattr = quote_name(source_col(resource, attribute))

    # The columns to write — every changeset attribute in the group except the temporal
    # range, which we build from `as_of`.
    insert_cols =
      changesets
      |> Enum.flat_map(fn cs -> Map.keys(Map.drop(cs.attributes, [attribute])) end)
      |> Enum.uniq()

    # On a match, set the configured `upsert_fields` (or all written columns), minus the
    # keys and the range itself.
    #
    # A match opens a new version, so it always takes the `recorded_at` the write was
    # stamped with, whether or not that is one of the `upsert_fields`.
    set_fields =
      (upsert_fields || insert_cols)
      |> Enum.concat(List.wrap(Ash.Resource.Info.temporal_recorded_at(resource)))
      |> Enum.uniq()
      |> Enum.filter(&(&1 in insert_cols))
      |> Kernel.--(upsert_keys)
      |> Kernel.--([attribute])

    qsrc = fn field -> quote_name(source_col(resource, field)) end

    # `$1` is `as_of`, the `VALUES` params follow it.
    {src_clause, row_params} =
      values_source(repo, resource, col_types, changesets, insert_cols, 2)

    params = [as_of | row_params]

    key_match = fn left ->
      Enum.map_join(upsert_keys, " AND ", fn k -> "#{left}.#{qsrc.(k)} = src.#{qsrc.(k)}" end)
    end

    has_update? = set_fields != []
    range = "tstzrange($1::timestamptz, NULL)"
    arbiter = quote_name(arbiter(resource, upsert_keys))
    columns = Enum.map(stored_columns(resource), &quote_name/1)
    upsert_cols = Enum.map(upsert_keys, qsrc)

    {gate_ctes, attempted} =
      if has_update? do
        set_sql = Enum.map_join(set_fields, ", ", fn f -> "#{qsrc.(f)} = src.#{qsrc.(f)}" end)

        matched =
          "FROM #{qtable} t JOIN src ON #{key_match.("t")} AND t.#{qattr} @> $1::timestamptz"

        {gate_ctes(matched, "t") <>
           "upd AS (UPDATE #{qtable} SET #{set_sql}, #{qattr} = #{tname}.#{qattr} * #{range} " <>
           "FROM src " <>
           "WHERE #{key_match.(tname)} AND #{tname}.#{qattr} @> $1::timestamptz " <>
           ~s|AND NOT (SELECT conflict FROM "__conflict") | <>
           ~s|RETURNING new AS "__new", old AS "__old"), | <>
           leftovers_cte(resource, qtable, "upd", range) <> ", ",
         ~s|NOT EXISTS (SELECT 1 FROM upd WHERE #{key_match.(~s|(upd."__new")|)})|}
      else
        {~s|"__conflict" AS (SELECT false AS conflict), |,
         "NOT EXISTS (SELECT 1 FROM #{qtable} ex WHERE #{key_match.("ex")} " <>
           "AND ex.#{qattr} @> $1::timestamptz)"}
      end

    # Bound the inserted range to this key's next period (gap-fill), else unbounded above
    # (NULL upper — the temporal "current" period; `'infinity'` can't be decoded).
    range_sql =
      "tstzrange($1::timestamptz, (SELECT min(lower(#{qattr})) FROM #{qtable} s2 " <>
        "WHERE #{key_match.("s2")} AND lower(#{qattr}) > $1::timestamptz))"

    insert_cols_sql = Enum.map_join(insert_cols ++ [attribute], ", ", qsrc)

    insert_select_sql =
      Enum.map_join(insert_cols, ", ", fn f -> "src.#{qsrc.(f)}" end) <> ", " <> range_sql

    # A key that loses an insert race to a concurrent write of the same record hits the
    # constraint behind the upsert keys. It's skipped rather than raised, and retried below.
    # Only that constraint is an arbiter, so any other identity's violation still raises.
    ins_cte =
      ~s|"__attempted" AS (SELECT * FROM src WHERE NOT (SELECT conflict FROM "__conflict") | <>
        "AND #{attempted}), " <>
        "ins AS (INSERT INTO #{qtable} (#{insert_cols_sql}) " <>
        ~s|SELECT #{insert_select_sql} FROM "__attempted" src | <>
        "ON CONFLICT ON CONSTRAINT #{arbiter} DO NOTHING " <>
        "RETURNING #{Enum.join(columns, ", ")})"

    written =
      if has_update? do
        ~s|SELECT #{Enum.map_join(columns, ", ", &~s|(upd."__new").#{&1}|)}, 'ok' AS "__status" | <>
          "FROM upd UNION ALL SELECT #{Enum.join(columns, ", ")}, 'ok' FROM ins"
      else
        ~s|SELECT #{Enum.join(columns, ", ")}, 'ok' AS "__status" FROM ins|
      end

    skipped_columns =
      Enum.map_join(columns, ", ", fn column ->
        if column in upsert_cols, do: "src.#{column}", else: "NULL"
      end)

    sql =
      "WITH #{src_clause}, #{gate_ctes}#{ins_cte} " <>
        written <>
        ~s| UNION ALL SELECT #{skipped_columns}, 'skipped' FROM "__attempted" src | <>
        "WHERE NOT EXISTS (SELECT 1 FROM ins WHERE #{key_match.("ins")}) " <>
        "UNION ALL SELECT #{Enum.map_join(columns, ", ", fn _ -> "NULL" end)}, 'conflict' " <>
        ~s|FROM "__conflict" WHERE conflict|

    {columns, %{"ok" => written, "skipped" => skipped, "conflict" => conflict}} =
      by_status(split!(repo, resource, sql, params))

    retry = fn retried ->
      if attempt < @attempts do
        upsert_group(
          repo,
          resource,
          qtable,
          col_types,
          retried,
          upsert_keys,
          upsert_fields,
          as_of,
          attempt + 1
        )
      else
        raise AshPostgres.Temporal.WriteConflict, resource: resource, attempts: @attempts
      end
    end

    cond do
      # Nothing was written, so run the whole group again.
      conflict != [] ->
        retry.(changesets)

      # Every other key was written, so run just the skipped ones again.
      skipped != [] ->
        skipped_keys =
          repo
          |> load_rows(resource, columns, skipped)
          |> MapSet.new(fn record -> Enum.map(upsert_keys, &Map.get(record, &1)) end)

        retried =
          Enum.filter(changesets, fn changeset ->
            Enum.map(upsert_keys, &Map.get(changeset.attributes, &1)) in skipped_keys
          end)

        records(repo, resource, columns, written, changesets, upsert_keys) ++
          retry.(retried)

      true ->
        records(repo, resource, columns, written, changesets, upsert_keys)
    end
  end

  defp records(repo, resource, columns, rows, changesets, upsert_keys) do
    repo
    |> load_rows(resource, columns, rows)
    |> tag_bulk_refs(changesets, upsert_keys)
  end

  defp split!(repo, resource, sql, params) do
    table = AshPostgres.DataLayer.Info.table(resource)
    pkey = "#{table}_pkey"

    try do
      repo.query!(sql, params)
    rescue
      e in Postgrex.Error ->
        case e do
          %{postgres: %{code: :unique_violation, constraint: ^pkey}} ->
            reraise AshPostgres.Temporal.PlainPrimaryKey.exception(
                      resource: resource,
                      table: table
                    ),
                    __STACKTRACE__

          _ ->
            reraise e, __STACKTRACE__
        end
    end
  end

  defp by_status(%{columns: columns, rows: rows}) do
    index = Enum.find_index(columns, &(&1 == "__status"))

    groups =
      rows
      |> Enum.group_by(&Enum.at(&1, index), &List.delete_at(&1, index))
      |> then(&Map.merge(%{"ok" => [], "skipped" => [], "conflict" => []}, &1))

    {List.delete_at(columns, index), groups}
  end

  defp arbiter(resource, upsert_keys) do
    table = AshPostgres.DataLayer.Info.table(resource)

    identity =
      Enum.find(Ash.Resource.Info.identities(resource), fn identity ->
        Enum.sort(identity.keys) == Enum.sort(upsert_keys)
      end)

    if is_nil(identity) or
         Enum.sort(upsert_keys) == Enum.sort(Ash.Resource.Info.primary_key(resource)) do
      "#{table}_pkey"
    else
      AshPostgres.DataLayer.Info.identity_index_names(resource)[identity.name] ||
        "#{table}_#{identity.name}_index"
    end
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

  # `src(<cols>) AS (VALUES ...)` over the changesets, with its params numbered from
  # `first`. The first row carries `::type` casts so Postgres knows each column's type.
  defp values_source(repo, resource, col_types, changesets, cols, first) do
    adapter = repo.__adapter__()
    col_count = length(cols)

    {rows_sql, row_params} =
      changesets
      |> Enum.with_index()
      |> Enum.map(fn {changeset, ri} ->
        cols
        |> Enum.with_index()
        |> Enum.map(fn {field, ci} ->
          n = first + ri * col_count + ci

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

    columns = Enum.map_join(cols, ", ", &quote_name(source_col(resource, &1)))

    {"src(#{columns}) AS (VALUES #{Enum.join(rows_sql, ", ")})", List.flatten(row_params)}
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

  # A period passes through; an instant opens one at it, unbounded above.
  defp portion(%Ash.Range{} = period), do: period
  defp portion(instant), do: %Ash.Range{lower: instant, upper: nil, bounds: :"[)"}

  @doc "Run a temporal UPDATE over `as_of`'s portion. Returns `{count, loaded_records | nil}`."
  def update_all(repo, query, resource, as_of, prefix \\ nil) do
    run(repo, :update_all, query, resource, as_of, prefix)
  end

  @doc "Run a temporal DELETE over `as_of`'s portion. Returns `{count, loaded_records | nil}`."
  def delete_all(repo, query, resource, as_of, prefix \\ nil) do
    run(repo, :delete_all, query, resource, as_of, prefix)
  end

  defp run(repo, kind, query, resource, as_of, prefix) do
    query = Map.delete(query, :__ash_bindings__)

    query =
      if prefix && !query.prefix, do: Ecto.Query.put_query_prefix(query, prefix), else: query

    returning? = not is_nil(query.select)
    %Ash.Range{lower: lower, upper: upper} = portion(as_of)

    # Render with the portion's bounds reserved as $1 (and $2 when it has an upper).
    counter = if upper, do: 2, else: 1
    {sql, params} = Ecto.Adapters.SQL.to_sql(kind, repo, query, counter: counter)

    range = "tstzrange($1::timestamptz, #{if upper, do: "$2::timestamptz", else: "NULL"})"
    sql = split_portion(sql, kind, resource, range, returning?)
    bounds = if upper, do: [lower, upper], else: [lower]
    result = write(repo, resource, sql, bounds ++ params)

    if returning? do
      {length(result.rows), load_rows(repo, resource, result.columns, result.rows)}
    else
      {result.rows |> hd() |> hd(), nil}
    end
  end

  # Rewrites Ecto's `UPDATE`/`DELETE` into the split described in the moduledoc.
  defp split_portion(sql, kind, resource, range, returning?) do
    [_, qtable, alias_token] =
      Regex.run(~r/^(?:UPDATE|DELETE FROM) ((?:"[^"]+"\.)?"[^"]+") AS (\w+) /, sql)

    period_col = quote_name(source_col(resource, temporal_attribute(resource)))
    period = alias_token <> "." <> period_col

    {dml, returned} =
      case find_top_level(sql, " RETURNING ") do
        nil -> {sql, nil}
        pos -> {take(sql, pos), drop(sql, pos + 11)}
      end

    dml =
      case kind do
        :update_all ->
          set_end =
            [find_top_level(dml, " FROM "), find_top_level(dml, " WHERE ")]
            |> Enum.reject(&is_nil/1)
            |> Enum.min(fn -> byte_size(dml) end)

          take(dml, set_end) <>
            ", #{period_col} = #{period} * #{range}" <> drop(dml, set_end)

        :delete_all ->
          dml
      end

    overlaps = "(#{period} && #{range})"

    dml =
      case find_top_level(dml, " WHERE ") do
        nil ->
          dml <> " WHERE " <> overlaps

        pos ->
          take(dml, pos) <> " WHERE (" <> drop(dml, pos + 7) <> ") AND " <> overlaps
      end

    # The versions the snapshot matched: the same table, joins and filter, as a SELECT.
    {from_keyword, from_pos} =
      case kind do
        :update_all -> {" FROM ", find_top_level(dml, " FROM ")}
        :delete_all -> {" USING ", find_top_level(dml, " USING ")}
      end

    where_pos = find_top_level(dml, " WHERE ")

    joined =
      if from_pos && from_pos < where_pos do
        start = from_pos + byte_size(from_keyword)
        ", " <> binary_part(dml, start, where_pos - start)
      else
        ""
      end

    matched = "FROM #{qtable} AS #{alias_token}#{joined}" <> drop(dml, where_pos)

    returning = Enum.join(List.wrap(returned) ++ [~s|old AS "__old"|], ", ")

    select =
      if returning? do
        # A range can carve several versions of one record; the write returns the first.
        columns = returned_columns(returned, alias_token)

        keys =
          resource
          |> Ash.Resource.Info.primary_key()
          |> Enum.map_join(", ", &"f.#{quote_name(source_col(resource, &1))}")

        ~s|(SELECT DISTINCT ON (#{keys}) #{Enum.map_join(columns, ", ", &"f.#{&1}")}, | <>
          ~s|'ok' AS "__status" FROM "__fpo" f ORDER BY #{keys}, lower(f.#{period_col})) | <>
          "UNION ALL SELECT #{Enum.map_join(columns, ", ", &"n.#{&1}")}, 'conflict' " <>
          ~s|FROM (SELECT (NULL::#{qtable}).*) n, "__conflict" WHERE conflict|
      else
        ~s|SELECT count(*), | <>
          ~s|(SELECT CASE WHEN conflict THEN 'conflict' ELSE 'ok' END FROM "__conflict") | <>
          ~s|AS "__status" FROM "__fpo"|
      end

    "WITH " <>
      gate_ctes(matched, alias_token) <>
      ~s|"__fpo" AS (#{dml} AND NOT (SELECT conflict FROM "__conflict") RETURNING #{returning}), | <>
      leftovers_cte(resource, qtable, ~s|"__fpo"|, range) <> " " <> select
  end

  # `"__cand"` is the versions `matched` (a `FROM ... WHERE ...`) finds in the snapshot, and
  # `"__locked"` is the same versions, locked. Locking waits out any concurrent write to a
  # version and then sees it as that write left it: changed (a newer row) or gone. So the
  # two differ exactly when a concurrent write got in the way, and `"__conflict"` says so.
  # The writes are gated on it, so a conflicting statement writes nothing.
  defp gate_ctes(matched, alias_token) do
    ~s|"__cand" AS (SELECT #{alias_token}.ctid #{matched}), | <>
      ~s|"__locked" AS (SELECT #{alias_token}.ctid #{matched} FOR UPDATE OF #{alias_token}), | <>
      ~s|"__conflict" AS (SELECT (| <>
      ~s|EXISTS (SELECT 1 FROM "__cand" c WHERE c.ctid NOT IN (SELECT ctid FROM "__locked")) OR | <>
      ~s|EXISTS (SELECT 1 FROM "__locked" l WHERE l.ctid NOT IN (SELECT ctid FROM "__cand"))| <>
      ~s|) AS conflict), |
  end

  # Runs a split, and runs it again while it reports a conflict (see the moduledoc). A
  # conflicting statement wrote nothing, so there's nothing to undo first.
  defp write(repo, resource, sql, params, attempt \\ 1) do
    case by_status(split!(repo, resource, sql, params)) do
      # Retried in a transaction, so the versions this attempt locked stay locked and can't
      # move again under the next one.
      {_, %{"conflict" => [_ | _]}} when attempt < @attempts ->
        transaction(repo, fn -> write(repo, resource, sql, params, attempt + 1) end)

      {_, %{"conflict" => [_ | _]}} ->
        raise AshPostgres.Temporal.WriteConflict, resource: resource, attempts: @attempts

      {columns, %{"ok" => rows}} ->
        %{columns: columns, rows: rows}
    end
  end

  # Ecto returns plain columns (`s0."id", s0."name"`); select them by name.
  defp returned_columns(returned, alias_token) do
    returned
    |> split_top_level(", ")
    |> Enum.map(fn item ->
      case Regex.run(~r/^#{alias_token}\.("[^"]+")$/, item) do
        [_, column] ->
          column

        nil ->
          raise ArgumentError,
                "Expected a plain column in temporal RETURNING, got: #{inspect(item)}"
      end
    end)
  end

  defp split_top_level(sql, separator) do
    case find_top_level(sql, separator) do
      nil ->
        [sql]

      pos ->
        [
          take(sql, pos)
          | split_top_level(drop(sql, pos + byte_size(separator)), separator)
        ]
    end
  end

  # Puts back what each version in `from` had outside the portion: every column copied
  # from `"__old"`, over `old - portion` (zero, one or two ranges).
  defp leftovers_cte(resource, qtable, from, range) do
    attribute = temporal_attribute(resource)
    period = quote_name(source_col(resource, attribute))

    columns =
      resource
      |> stored_columns()
      |> Enum.reject(&(&1 == source_col(resource, attribute)))
      |> Enum.map(&quote_name/1)

    ~s|"__leftovers" AS (INSERT INTO #{qtable} (#{Enum.join(columns ++ [period], ", ")}) | <>
      "OVERRIDING SYSTEM VALUE " <>
      ~s|SELECT #{Enum.map_join(columns, ", ", &~s|(f."__old").#{&1}|)}, l.r | <>
      ~s|FROM #{from} f, unnest(multirange((f."__old").#{period}) - multirange(#{range})) AS l(r))|
  end

  defp stored_columns(resource) do
    resource.__schema__(:fields)
    |> Enum.map(&resource.__schema__(:field_source, &1))
  end

  # A partly retried upsert must commit or roll back as a whole.
  defp transaction(repo, fun) do
    if repo.in_transaction?() do
      fun.()
    else
      {:ok, result} = repo.transaction(fun)
      result
    end
  end

  defp temporal_attribute(resource), do: Ash.Resource.Info.temporal_attribute(resource)

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

  defp find_top_level(sql, pattern), do: scan(sql, pattern, 0, 0, :normal)

  defp scan(<<>>, _pattern, _pos, _depth, _state), do: nil

  defp scan(<<char, rest::binary>> = sql, pattern, pos, depth, :normal) do
    if depth == 0 and String.starts_with?(sql, pattern) do
      pos
    else
      case char do
        ?' -> scan(rest, pattern, pos + 1, depth, :single_quote)
        ?" -> scan(rest, pattern, pos + 1, depth, :double_quote)
        ?( -> scan(rest, pattern, pos + 1, depth + 1, :normal)
        ?) when depth > 0 -> scan(rest, pattern, pos + 1, depth - 1, :normal)
        _ -> scan(rest, pattern, pos + 1, depth, :normal)
      end
    end
  end

  defp scan(<<"''", rest::binary>>, pattern, pos, depth, :single_quote),
    do: scan(rest, pattern, pos + 2, depth, :single_quote)

  defp scan(<<"'", rest::binary>>, pattern, pos, depth, :single_quote),
    do: scan(rest, pattern, pos + 1, depth, :normal)

  defp scan(<<_, rest::binary>>, pattern, pos, depth, :single_quote),
    do: scan(rest, pattern, pos + 1, depth, :single_quote)

  defp scan(<<"\"\"", rest::binary>>, pattern, pos, depth, :double_quote),
    do: scan(rest, pattern, pos + 2, depth, :double_quote)

  defp scan(<<"\"", rest::binary>>, pattern, pos, depth, :double_quote),
    do: scan(rest, pattern, pos + 1, depth, :normal)

  defp scan(<<_, rest::binary>>, pattern, pos, depth, :double_quote),
    do: scan(rest, pattern, pos + 1, depth, :double_quote)

  # Slices by the byte offsets `find_top_level/2` returns.
  defp take(binary, count), do: binary_part(binary, 0, count)
  defp drop(binary, count), do: binary_part(binary, count, byte_size(binary) - count)
end
