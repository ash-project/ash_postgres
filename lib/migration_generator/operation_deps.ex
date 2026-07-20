# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationGenerator.OperationDeps do
  @moduledoc """
  Computes the dependency graph used to order migration operations.

  Each operation may *provide* facts (things that become true once it runs)
  and *require* facts (things that must already be true before it can run).
  `AshPostgres.MigrationGenerator.MigrationGenerator.toposort_operations/1`
  turns these into a dependency graph and topologically sorts it.

  There is deliberately no symmetric "late tier" counterpart to
  `early_tier?/1` (a global "runs after everything else" barrier). Adding one
  creates a real cycle: anything that requires a same-table fact regardless
  of provider (e.g. `AddCustomStatement` requiring its own table's structure
  to be ready) would need that "late" op to run first, while the "late" op's
  barrier would need it to run last — contradictory. Give each operation
  type the ordering it needs via `requires/1` instead.

  Requiring a fact waits on *every* operation that provides it, not just one
  — see `toposort_operations/1`'s `provides_index`. That's what makes
  `:table_structure_ready` work as a catch-all: many operation types provide
  it, so an op that requires it (currently only `AddCustomStatement`'s
  own-table requirement) transparently waits for all of that table's
  structural work, without needing to enumerate every attribute/index/
  constraint by hand.

  Requiring a fact that nothing in the current batch provides is vacuously
  satisfied — it adds no dependency edge at all, rather than blocking or
  raising. This is intentional: e.g. `reference_requirements/1` requires a
  referenced table/column to be `:column_ready`, but if that table already
  exists from an earlier migration (so nothing in *this* batch provides the
  fact), the requirement is trivially met and doesn't hold anything up.

  A generated migration's `down` isn't independently derived — it's built by
  walking the same operation order in reverse and rendering each operation's
  `down/1` (see `MigrationGenerator.build_up_and_down/1`). So an ordering
  that's harmless for `up` can still be wrong: if `RenameAttribute` isn't
  required to run after a `RemoveCustomIndex` on the same table, `down` ends
  up recreating that index (`RemoveCustomIndex.down`) *before* undoing the
  rename, referencing a column name that doesn't exist yet at that point.
  Postgres itself doesn't need indexes/constraints removed before a rename or
  a column drop — it tracks index predicates, expression indexes, and
  same-table constraints internally by column position and updates or drops
  them automatically (verified directly: a partial unique index's `WHERE`
  clause and a custom index's expression are both rewritten after `RENAME
  COLUMN`; a `CHECK` constraint on a dropped column is dropped with it, no
  `CASCADE` needed). But several facts below exist anyway, purely so the
  *reversed* `down` sequence stays valid. Only genuinely cross-table
  dependencies (a foreign key on another table) block a Postgres statement
  directly, which is what `:column_fk_dropped` is for.

  ## Facts

  Each fact is a 2-tuple `{name, key}`. `key` is `{schema, table}` for a
  table-scoped fact, or `{schema, table, x}` for a fact scoped to some `x`
  within that table — see `key/2`, `key/3`. That third element is a column
  for every fact below except `:custom_index_removed`, where it's an index
  name; facts are named `table_*`/`column_*`/`index_*` to match what their
  key actually scopes over, not just its shape.

  Table-scoped (`key = {schema, table}`):

  These first three track "how done is this table", but not as one single
  chain — `:table_ready` is provided by a disjoint set of operations
  (`CreateTable`/`RenameTable`/`MoveTableSchema`) from `:table_columns_settled`
  (`AddAttribute`/`RenameAttribute`/`AlterAttribute`/`RemoveAttribute`), so
  requiring both together is *not* redundant — neither subsumes the other.
  Both converge at `:table_structure_ready`, which every structural operation
  provides:

  - `:table_ready` — the table exists (`CreateTable`/`RenameTable`/
    `MoveTableSchema`).
  - `:table_columns_settled` — every attribute add/alter/rename/remove for
    this table has already run — a conservative margin for consumers whose
    raw SQL (a filtered unique index's `where`, a custom index's expression,
    a check constraint's `check:`) might reference a column that's about to
    be added, altered, renamed, or removed, and can't be parsed to know
    which columns it actually touches.
  - `:table_structure_ready` — provided by every structural operation on this
    table (including `:table_ready`'s and `:table_columns_settled`'s
    providers); a consumer requires it once to mean "wait for all of this
    table's structural work".

  Column-scoped (`key = {schema, table, column}`):

  - `:column_ready` — a specific column (by its current name) exists.
  - `:column_unique_index_created` — a specific column is now covered by a
    unique index (satisfies FK targets referencing it — Postgres requires a
    foreign key's target to be backed by a unique constraint/index).
  - `:column_unique_index_removed` — the inverse: a specific column's unique
    index has been removed. `RenameAttribute` requires this for the same
    `down`-validity reason as `:column_custom_index_removed`.
  - `:column_custom_index_removed` — every `RemoveCustomIndex` whose
    structured `fields` list includes this column has run. `RenameAttribute`
    requires this for its own column so `down` stays valid (see above). Only
    tracks `fields`, not raw `where`/expression text that might reference
    the column without listing it — a known gap, to be closed later by
    letting `custom_indexes` declare the columns a raw `where`/expression
    touches, rather than by conservatively widening this back to table
    scope.
  - `:column_check_constraint_removed` — every check constraint covering
    this column has been removed. `RemoveAttribute`/`RenameAttribute`
    require this for their own column so `down` stays valid: their `down`
    recreates/renames the column back, which must happen *before*
    `RemoveCheckConstraint`'s `down` recreates a constraint that needs it —
    i.e. `RemoveCheckConstraint` must run first in `up`.
  - `:column_fk_dropped` — every foreign key on another table that
    referenced this specific column has been dropped (`direction: :up`).
    Postgres refuses to drop a unique constraint/primary key that's still
    referenced by another table's foreign key (verified directly, and not
    limited to primary keys), so `RemovePrimaryKey`/`RemoveUniqueIndex`
    require this for each of their own columns.
  - `:reference_index_removed` — the reference index on this FK column has
    been dropped (`RemoveReferenceIndex`). `AddReferenceIndex` requires this
    for its own source column: both derive the same auto-generated index
    name from their columns, so rewriting an existing reference index
    (a Remove/Add pair, e.g. when its `index_where` predicate changes) must
    drop the old index before creating the new one.

  Index-scoped (`key = {schema, table, index}`, same shape as a column-scoped
  key but the third element is an index name, not a column):

  - `:custom_index_removed` — a specific *named* custom index has been
    dropped, so a same-named index can be recreated (Postgres index names
    are unique per schema).
  """

  alias AshPostgres.MigrationGenerator.Operation

  @doc "Operation types that must run before every other operation in the batch."
  def early_tier?(op) do
    match?(%Operation.DropTable{}, op) ||
      match?(%Operation.RemoveCustomStatement{}, op) ||
      match?(%Operation.AlterDeferrability{direction: :down}, op) ||
      match?(%Operation.RemovePrimaryKey{}, op) ||
      match?(%Operation.AddPrimaryKeyDown{}, op)
  end

  @doc "Facts made true once `op` has run."
  def provides(op) do
    case op do
      %Operation.CreateTable{table: table, schema: schema} ->
        [{:table_ready, key(table, schema)}, {:table_structure_ready, key(table, schema)}]

      %Operation.RenameTable{table: table, schema: schema} ->
        [{:table_ready, key(table, schema)}, {:table_structure_ready, key(table, schema)}]

      %Operation.MoveTableSchema{table: table, new_schema: schema} ->
        [{:table_ready, key(table, schema)}, {:table_structure_ready, key(table, schema)}]

      %Operation.AddAttribute{table: table, schema: schema, attribute: attribute} ->
        [
          {:column_ready, key(table, schema, attribute.source)},
          {:table_columns_settled, key(table, schema)},
          {:table_structure_ready, key(table, schema)}
        ]

      %Operation.RenameAttribute{
        table: table,
        schema: schema,
        new_attribute: new_attribute
      } ->
        [
          {:column_ready, key(table, schema, new_attribute.source)},
          {:table_columns_settled, key(table, schema)},
          {:table_structure_ready, key(table, schema)}
        ]

      %Operation.AlterAttribute{table: table, schema: schema} ->
        [
          {:table_columns_settled, key(table, schema)},
          {:table_structure_ready, key(table, schema)}
        ]

      %Operation.RemoveAttribute{table: table, schema: schema} ->
        [
          {:table_columns_settled, key(table, schema)},
          {:table_structure_ready, key(table, schema)}
        ]

      %Operation.AddUniqueIndex{table: table, schema: schema, identity: identity} ->
        keys = List.wrap(identity.keys)

        [{:table_structure_ready, key(table, schema)}] ++
          Enum.map(keys, &{:column_unique_index_created, key(table, schema, &1)})

      %Operation.RemoveUniqueIndex{table: table, schema: schema, identity: identity} ->
        keys = List.wrap(identity.keys)

        [{:table_structure_ready, key(table, schema)}] ++
          Enum.map(keys, &{:column_unique_index_removed, key(table, schema, &1)})

      %Operation.AddCustomIndex{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.RemoveCustomIndex{table: table, schema: schema, index: index} ->
        base =
          [{:table_structure_ready, key(table, schema)}] ++
            Enum.map(index.fields, fn field ->
              {:column_custom_index_removed,
               key(table, schema, AshPostgres.CustomIndex.column_name(field))}
            end)

        # An index without an explicit `name:` gets one auto-derived by
        # Postgres/Ecto from its columns, so two *different* unnamed indexes
        # would otherwise collide on the same `nil` fact key and get
        # spuriously coupled — only track this for explicitly named indexes,
        # where a real name collision is possible.
        if index.name do
          [{:custom_index_removed, key(table, schema, index.name)} | base]
        else
          base
        end

      %Operation.AddReferenceIndex{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.RemoveReferenceIndex{table: table, schema: schema, source: source} ->
        [
          {:table_structure_ready, key(table, schema)},
          {:reference_index_removed, key(table, schema, source)}
        ]

      %Operation.AddCheckConstraint{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.RemoveCheckConstraint{
        table: table,
        schema: schema,
        constraint: constraint,
        multitenancy: multitenancy
      } ->
        cols = check_constraint_columns(constraint, multitenancy)

        [{:table_structure_ready, key(table, schema)}] ++
          Enum.map(cols, &{:column_check_constraint_removed, key(table, schema, &1)})

      %Operation.DropForeignKey{
        table: table,
        schema: schema,
        direction: :up,
        attribute: %{
          references: %{table: dest_table, destination_attribute: dest_column} = reference
        }
      } ->
        dest_schema = Map.get(reference, :schema)

        [
          {:column_fk_dropped, key(dest_table, dest_schema, dest_column)},
          {:table_structure_ready, key(table, schema)}
        ]

      %Operation.DropForeignKey{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.AlterDeferrability{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.AddPrimaryKey{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.AddPrimaryKeyDown{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.RemovePrimaryKey{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      %Operation.RemovePrimaryKeyDown{table: table, schema: schema} ->
        [{:table_structure_ready, key(table, schema)}]

      _ ->
        []
    end
  end

  @doc "Facts that must already be provided (by some other operation) before `op` can run."
  def requires(op) do
    case op do
      %Operation.AddAttribute{table: table, schema: schema, attribute: attribute} ->
        [{:table_ready, key(table, schema)}] ++ reference_requirements(attribute)

      %Operation.AlterAttribute{
        table: table,
        schema: schema,
        new_attribute: new_attribute,
        old_attribute: old_attribute
      } ->
        # `old_attribute.source` is normally the current column name, but when
        # a rename and a property change (type/null/default) land in the same
        # diff, `old_attribute` here is the *pre-rename* attribute (see
        # `attribute_operations/4`) while a separate `RenameAttribute` op
        # handles the physical rename to `new_attribute.source`. Requiring
        # both names' `column_ready` fact covers both cases: the common case
        # (no rename, both sources equal, so this is a no-op duplicate) and
        # the rename+alter case (only `new_attribute.source` has a provider —
        # the `RenameAttribute` op — so the alter correctly waits for it).
        [
          {:table_ready, key(table, schema)},
          {:column_ready, key(table, schema, old_attribute.source)},
          {:column_ready, key(table, schema, new_attribute.source)}
        ] ++ reference_requirements(new_attribute)

      %Operation.RenameAttribute{table: table, schema: schema, old_attribute: old_attribute} ->
        [
          {:table_ready, key(table, schema)},
          {:column_ready, key(table, schema, old_attribute.source)},
          {:column_unique_index_removed, key(table, schema, old_attribute.source)},
          {:column_check_constraint_removed, key(table, schema, old_attribute.source)},
          # This table's `down` sequence is this same operation list reversed
          # (see moduledoc), so a RemoveCustomIndex covering this column must
          # run first in `up` — otherwise its `down` (recreating the index)
          # would run before this rename's `down` undoes the rename,
          # referencing a column name that doesn't exist yet. Only tracks
          # the index's structured `fields` list, not raw `where`/expression
          # text that might reference this column without listing it —
          # accepted gap for now (see moduledoc note on custom_index_removed).
          {:column_custom_index_removed, key(table, schema, old_attribute.source)}
        ]

      %Operation.RemoveAttribute{table: table, schema: schema, attribute: attribute} ->
        [
          {:table_ready, key(table, schema)},
          {:column_check_constraint_removed, key(table, schema, attribute.source)}
        ]

      %Operation.AddUniqueIndex{
        table: table,
        schema: schema,
        identity: identity,
        insert_after_attribute_source: source
      } ->
        base = [{:table_ready, key(table, schema)}]

        # `where`/`base_filter` on a unique index (e.g. a soft-delete scoped
        # identity filtering on `archived_at IS NULL`) can reference columns
        # that aren't otherwise declared as this index's keys, and there's no
        # structured way to know which ones without parsing raw SQL. Requiring
        # every column op on the table (same margin `AddCustomIndex` already
        # takes) is the safe choice — but only when such a filter actually
        # exists: unconditionally requiring this would also pull in a
        # self-referencing attribute whose own FK targets *this* index (e.g.
        # a self-referential `belongs_to`), creating a genuine two-way
        # dependency cycle between that attribute and this index.
        base =
          if Map.get(identity, :where) || Map.get(identity, :base_filter) do
            [{:table_columns_settled, key(table, schema)} | base]
          else
            base
          end

        if source do
          [{:column_ready, key(table, schema, source)} | base]
        else
          base
        end

      %Operation.RemoveUniqueIndex{table: table, schema: schema, identity: identity} ->
        keys = List.wrap(identity.keys)

        # Postgres refuses to drop a unique constraint/index that's still
        # referenced by another table's foreign key (the same restriction
        # `RemovePrimaryKey` has, just not limited to the primary key —
        # verified directly: dropping a non-PK UNIQUE constraint still
        # referenced by an FK raises "other objects depend on it").
        [{:table_ready, key(table, schema)}] ++
          Enum.map(keys, &{:column_fk_dropped, key(table, schema, &1)})

      %Operation.AddCustomIndex{table: table, schema: schema, index: index} ->
        base = [
          {:table_ready, key(table, schema)},
          {:table_columns_settled, key(table, schema)}
        ]

        # a `RemoveCustomIndex` sharing this index's *explicit* name must run
        # first — Postgres can't create an index under a name that's still in
        # use. See the matching guard in `provides/1`.
        if index.name do
          [{:custom_index_removed, key(table, schema, index.name)} | base]
        else
          base
        end

      %Operation.AddReferenceIndex{table: table, schema: schema, source: source} ->
        # a `RemoveReferenceIndex` on the same source column must run first —
        # both derive the same auto-generated index name from their columns,
        # so Postgres can't create the new index while the old one exists.
        [
          {:table_ready, key(table, schema)},
          {:table_columns_settled, key(table, schema)},
          {:reference_index_removed, key(table, schema, source)}
        ]

      %Operation.AddCheckConstraint{
        table: table,
        schema: schema,
        constraint: constraint,
        multitenancy: multitenancy
      } ->
        cols = check_constraint_columns(constraint, multitenancy)

        [{:table_ready, key(table, schema)}, {:table_columns_settled, key(table, schema)}] ++
          Enum.map(cols, &{:column_ready, key(table, schema, &1)})

      %Operation.RemoveCheckConstraint{table: table, schema: schema} ->
        [{:table_ready, key(table, schema)}]

      %Operation.DropForeignKey{table: table, schema: schema} ->
        [{:table_ready, key(table, schema)}]

      %Operation.RemovePrimaryKey{table: table, schema: schema, keys: keys} ->
        Enum.map(List.wrap(keys), &{:column_fk_dropped, key(table, schema, &1)})

      %Operation.AddCustomStatement{table: own_table, schema: schema} ->
        [{:table_structure_ready, key(own_table, schema)}]

      _ ->
        []
    end
  end

  defp reference_requirements(%{
         references: %{table: table, destination_attribute: column} = reference
       }) do
    schema = Map.get(reference, :schema)

    [
      {:column_ready, key(table, schema, column)},
      {:column_unique_index_created, key(table, schema, column)}
    ]
  end

  defp reference_requirements(_), do: []

  defp check_constraint_columns(constraint, multitenancy) do
    cols = List.wrap(Map.get(constraint, :attribute))

    if multitenancy && Map.get(multitenancy, :attribute) do
      Enum.uniq([multitenancy.attribute | cols])
    else
      cols
    end
  end

  # `op.schema` (a resource's own postgres schema option) defaults to `nil` for
  # the default schema, but `attribute.references.schema` (the *destination*
  # schema recorded on a foreign key) is instead loaded from the snapshot as
  # the literal string `"public"` (see `load_attribute/2` in
  # migration_generator.ex, which only `Map.put_new/3`s a default and leaves
  # an explicit `"public"` alone). Without normalizing these to the same
  # value, a same-table fact key built from `op.schema` (`nil`) would never
  # match a cross-table reference fact key built from `reference.schema`
  # (`"public"`) even though they mean the same schema, silently dropping the
  # ordering dependency.
  defp key(table, schema), do: {normalize_schema(schema), table}
  defp key(table, schema, col), do: {normalize_schema(schema), table, col}

  defp normalize_schema(nil), do: "public"
  defp normalize_schema(schema), do: schema
end
