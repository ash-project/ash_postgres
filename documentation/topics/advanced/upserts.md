<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Upserts

Create actions with `upsert? true`, `Ash.create/2` with `upsert?: true`, and `Ash.bulk_create/4` with `upsert?: true` are all executed as a single `INSERT ... ON CONFLICT DO UPDATE` statement. The conflict target is the upsert identity (or the primary key when no identity is given), and the `DO UPDATE` clause sets the `upsert_fields` from the incoming row, applying any `upsert_condition` as its `WHERE`.

## Knowing whether a record was inserted or updated

Every record returned from an upsert carries `:upsert_action` metadata, either `:insert` or `:update`:

```elixir
post = Ash.create!(changeset, upsert?: true)
Ash.Resource.get_metadata(post, :upsert_action)
# => :insert | :update
```

This works on every supported PostgreSQL version. It is derived from the row's system column in the statement's `RETURNING` clause (`xmax = 0` for a freshly inserted row version, non-zero for one written by the `DO UPDATE` branch).

Records that were skipped because the `upsert_condition` did not hold are not returned unless you pass `return_skipped_upsert?: true`, in which case they are tagged with `:upsert_skipped` metadata instead.

## Identities that need SQL

PostgreSQL resolves the conflict target against a unique index, so the identity used for an upsert must have a matching unique index (the migration generator creates one per identity). Some identities need extra information to be rendered as a conflict target:

- An identity with a `where` clause matches a partial unique index, and PostgreSQL requires the same predicate in the statement. Provide it with `identity_wheres_to_sql` in the `postgres` section (see `AshPostgres.DataLayer.Info.identity_wheres_to_sql/1`).
- A resource with a `base_filter` needs `base_filter_sql`, for the same reason.
- An identity over a calculation matches an expression index, and needs the expression's SQL from `calculations_to_sql`.

## Concurrency

`INSERT ... ON CONFLICT` is the only PostgreSQL statement that arbitrates concurrent inserts of the same key. When two transactions upsert the same identity at the same time, the second waits for the first to commit and then takes the `DO UPDATE` branch, so both succeed and the row ends up with the last writer's values. This holds under the default `READ COMMITTED` isolation level. Under `REPEATABLE READ` or `SERIALIZABLE`, PostgreSQL may instead raise a serialization failure, as with any concurrent write.

This is also why upserts are not implemented with `MERGE` on PostgreSQL 17+ (versions 2.10 to 2.13 did this): `MERGE` evaluates its `ON` condition against a snapshot and does not wait for concurrent inserts, so two concurrent upserts of the same key both take the `WHEN NOT MATCHED` branch and the loser fails with a unique constraint violation.
