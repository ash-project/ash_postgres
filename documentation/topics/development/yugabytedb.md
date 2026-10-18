<!--
SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# YugabyteDB

YugabyteDB's YSQL API speaks the PostgreSQL protocol, so AshPostgres can connect
through Ecto and Postgrex. It does not implement every PostgreSQL feature.
The dedicated integration suite tests a small compatibility surface against
**YugabyteDB 2026.1.2.0-b137**, whose YSQL layer is based on PostgreSQL 15.
This is not a claim that the entire AshPostgres suite or all YugabyteDB versions
are supported.

## Repo configuration

YugabyteDB does not provide the PostgreSQL `xmax` system column used to distinguish
inserted rows from updated rows during upserts. Disable that metadata in your repo:

```elixir
defmodule MyApp.Repo do
  use AshPostgres.Repo, otp_app: :my_app

  @impl AshPostgres.Repo
  def include_upsert_action?, do: false

  @impl AshPostgres.Repo
  def min_pg_version, do: %Version{major: 15, minor: 0, patch: 0}
end
```

Single and bulk upserts still use `INSERT ... ON CONFLICT` and can return ordinary
record fields. `Ash.Resource.get_metadata(record, :upsert_action)` returns `nil`;
it cannot tell you whether an upsert inserted or updated a row. Skipped-upsert
metadata is unaffected. See [Upserts](upserts.md#databases-without-xmax).

The PostgreSQL version here describes the SQL features available from YSQL, not
the YugabyteDB product version. Do not set it to 18 to enable features that the
server does not implement. Older YugabyteDB releases use a different PostgreSQL
baseline; consult the [YSQL compatibility documentation](https://docs.yugabyte.com/stable/faq/compatibility/).

Configure the usual Ecto connection options for your deployment, including its
TLS and authentication requirements. Only list extensions in
`installed_extensions/0` that are available and installed on that server. The
integration suite uses no extensions and generates UUIDs in the application.

## Migrations

YugabyteDB's [transactional DDL](https://docs.yugabyte.com/stable/architecture/transactions/transactional-ddl/)
is an opt-in early-access feature. For deployments without it, add this attribute
to migrations, including migrations produced by the AshPostgres generator:

```elixir
use Ecto.Migration

@disable_ddl_transaction true
```

Without a DDL transaction, a failure can leave a partially applied migration.
Review the resulting schema before retrying; rolling back the transaction does
not undo those DDL statements.

The disposable test repo also sets `migration_lock: false` and runs one migrator.
That is a test setup choice, not a recommendation to run concurrent production
migrators without coordination. Choose migration locking appropriate to your
YugabyteDB version and deployment, or serialize migrations externally.

## Tested behavior and limits

The suite exercises real Ash actions against a single-node database:

- Ordinary create, read, update, and destroy actions.
- Single upserts using an identity and primary-key upserts with selected fields.
- Bulk upserts containing both inserts and updates, with and without returned records.
- Omission of `:upsert_action`, while retaining `:upsert_skipped` for conditional upserts.
- Transaction rollback of an upsert and an ordinary create.
- Translation of a unique-constraint violation into an Ash error.

The fixture uses a basic table and unique index, migrated outside a DDL transaction.
It does not certify the migration generator's full output, optional extensions,
schema-based multitenancy, distributed failover, or concurrent-write retry behavior.

Temporal resources require PostgreSQL 18 features, GiST exclusion constraints,
and row-version behavior beyond this compatibility surface. See
[Temporal Resources](temporal-resources.md) and YugabyteDB's
[PostgreSQL compatibility limits](https://docs.yugabyte.com/stable/develop/postgresql-compatibility/)
before adopting PostgreSQL-specific features.

## Running the integration suite

Use a disposable database. The suite migrates `ash_postgres_yugabyte_test` and
deletes rows from its `items` table before and after each test. Its dedicated
`yugabyte` Mix environment does not start the ordinary PostgreSQL test repos or
run their migrations.

Start the same version used by CI:

```sh
docker run --detach --name ash-postgres-yugabyte --init \
  --publish 127.0.0.1:5433:5433 \
  yugabytedb/yugabyte:2026.1.2.0-b137 bin/yugabyted start \
  --background=false --advertise_address=127.0.0.1 \
  --ui=false --callhome=false \
  --tserver_flags=pgsql_proxy_bind_address=0.0.0.0:5433
```

This local container has no authentication or TLS and exposes only YSQL on
loopback. It is for testing, not deployment. Once YSQL is ready (the following
`SELECT` succeeds), create the test database and run the suite:

```sh
docker exec ash-postgres-yugabyte bin/ysqlsh -h 127.0.0.1 \
  -U yugabyte -d yugabyte -v ON_ERROR_STOP=1 -c 'SELECT 1'
docker exec ash-postgres-yugabyte bin/ysqlsh -h 127.0.0.1 \
  -U yugabyte -d yugabyte -v ON_ERROR_STOP=1 \
  -c 'CREATE DATABASE ash_postgres_yugabyte_test'

MIX_ENV=yugabyte mix deps.get
MIX_ENV=yugabyte mix test
```

The suite prints the server version and refuses to run against ordinary
PostgreSQL. Connection overrides are `YUGABYTE_HOST`, `YUGABYTE_PORT`,
`YUGABYTE_USER`, and `YUGABYTE_PASSWORD`; the database name stays fixed.
For example, map a different host port and set `YUGABYTE_PORT` if 5433 is occupied.

Remove the disposable database container when finished:

```sh
docker rm --force ash-postgres-yugabyte
```

The normal PostgreSQL suite is unchanged and still runs with `mix test`.
