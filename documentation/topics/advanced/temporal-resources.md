<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Temporal Resources

A temporal resource remembers everything. Every record is spread across many rows, one for
each period of its history, and you can read it as of any moment. Ash's
[temporal resources guide](https://hexdocs.pm/ash/temporal-resources.html) covers what they are
and how to use them. This page is about what AshPostgres does underneath, and what it needs from
you.

## What you need

PostgreSQL 18 or later. That's where periods arrived in primary keys and foreign keys, which is
what all of this is built on. Your repo has to say it's targeting 18:

```elixir
def min_pg_version do
  %Version{major: 18, minor: 0, patch: 0}
end
```

You also need the `btree_gist` extension. A temporal primary key is a GiST exclusion constraint
under the hood, and `btree_gist` is what lets it compare ordinary columns like `id`:

```elixir
def installed_extensions do
  ["ash-functions", "btree_gist"]
end
```

Forget either one, and your temporal resource won't compile. The error tells you which.

## What ends up in your database

Run `mix ash_postgres.generate_migrations` and you get:

- **A period column**, a `tstzrange` holding the period each row is valid for.
- **`PRIMARY KEY (id, valid_at WITHOUT OVERLAPS)`**, so a record can have as many rows as it
  likes, but never two that are valid at the same instant.
- **`PERIOD` foreign keys** for relationships between temporal resources. A subscription can't
  point at a plan for a stretch of time when that plan didn't exist.
- **Identities that are unique at every instant**, rather than across all of time. Two members
  can't share an email at the same moment, but an email that one member gave up can go to
  another.

## How a write splits a row

Say a subscription has been on bronze since January, and you change it to gold as of March 1.
Nothing gets overwritten. The bronze row is cut off at March 1, and a gold row picks up from
there:

```text
before:  [Jan 1, ∞)  bronze

after:   [Jan 1, Mar 1)  bronze
         [Mar 1, ∞)      gold
```

The SQL standard has a statement for exactly this: `UPDATE ... FOR PORTION OF`. Here's a plot
twist, though. It was slated for PostgreSQL 19, and temporal resources were first built on it.
Then we found that PostgreSQL had
[reverted it](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=a4b26b8f7cd07a3e7f0cba550c30db142329e065)
before release: two writes to the same row at the same time could quietly lose part of one of
them.

So AshPostgres does the split itself. Each write is a single statement that writes the slice it
covers, and puts back the rest of the row as new rows next to it. A destroy works the same way,
except the slice it covers is simply gone. When PostgreSQL ships `FOR PORTION OF` for real,
AshPostgres will switch to it.

## When two writes collide

That lost-update problem doesn't go away just because we're doing the split ourselves, so here's
how AshPostgres handles it.

Every temporal write locks the rows it's about to split, and checks that they're still the rows
it expected to find. Usually they are, and the write goes ahead. But if another transaction got
there first and changed one of them, the write backs off without writing anything, and tries
again. From then on it holds on to every lock it takes, so it doesn't keep losing its place in
line. Two upserts that race to create the same record are sorted out the same way: the one that
loses, retries.

You'll almost never notice. It takes a lot of transactions hammering the same part of the same
record at once to make a write retry more than a couple of times. If one ever loses 25 times in a
row, it gives up with `AshPostgres.Temporal.WriteConflict`. Nothing was written, so it's safe to
just try the action again.

That's all under `READ COMMITTED`, which is what you're using unless you've changed it. Under
`REPEATABLE READ` or `SERIALIZABLE`, PostgreSQL raises a serialization failure for these collisions
itself, and retrying is up to you.

One thing to keep in mind: the locking only happens for writes that go through Ash. If something
else writes to your temporal tables with raw SQL at the same moment, it can still step on Ash's
writes.
