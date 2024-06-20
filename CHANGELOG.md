# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v2.0.11](https://github.com/ash-project/ash_postgres/compare/v2.0.10...v2.0.11) (2024-06-19)

### Bug Fixes:

- [AshPostgres.DataLayer] rework expression type detection

- [migration generator] ensure index keys are atoms in generated migrations (#332)

## [v2.0.10](https://github.com/ash-project/ash_postgres/compare/v2.0.9...v2.0.10) (2024-06-18)

### Bug Fixes:

- [AshPostgres.DataLayer] update ash_sql to fix query generation issues

- [migration generator] ensure that parens are always added to calculation generated SQL

- [migration generator] properly get calculation sql

### Improvements:

- [AshPostgres.DataLayer] better type handling using new type inference

- [identities] identities w/ calculations and where clauses in upserts

## [v2.0.9](https://github.com/ash-project/ash_postgres/compare/v2.0.8...v2.0.9) (2024-06-13)

### Features:

- [migration generator] autogenerate index in references (#321)

### Bug Fixes:

- [AshPostgres.DataLayer] fix invalid select on sorting by some calculations

- [AshPostgres.DataLayer] fix error message displaying in identity verifier

- [lateral joining] ensure that context multitenancy is properly applied to lateral many-to-many joins

- [migration generator] don't assume old snapshots have `index?` key for attributes

- [ash.rollback] `list_tenants` -> `all_tenants`

- [ash.rollback] when checking for roll back-able migrations, only check `Path.basename`

### Improvements:

- [migration generator] don't sort identity keys.

## [v2.0.8](https://github.com/ash-project/ash_postgres/compare/v2.0.7...v2.0.8) (2024-06-06)

## [v2.0.7](https://github.com/ash-project/ash_postgres/compare/v2.0.6...v2.0.7) (2024-06-06)

### Bug Fixes:

- [fix] update ash_sql and fix issues retaining lateral join context

- [fix] ensure that all current attribute values are selected on bulk update shifted root query

## [v2.0.6](https://github.com/ash-project/ash_postgres/compare/v2.0.5...v2.0.6) (2024-05-29)

### Bug Fixes:

- [atomic updates] properly support aggregate references in atomic updates

- [migration generator] ensure that identities are dropped when where/nils_distinct? are changed

- [migration generator] ensure that `where` is wrapped in parenthesis

- [ecto compatibility] support old/new parameterized type format

### Improvements:

- [identities] require clarification of index names > 63 characters

- [mix ash_postgres.squash_snapshots] add `ash_postgres.squash_snapshots` mix task (#302)

## [v2.0.5](https://github.com/ash-project/ash_postgres/compare/v2.0.4...v2.0.5) (2024-05-24)

### Improvements:

- [idenities] update `ash` and support new `identity` features

## [v2.0.4](https://github.com/ash-project/ash_postgres/compare/v2.0.3...v2.0.4) (2024-05-23)

### Bug Fixes:

[updates] ensure update's reselect all changing values

## [v2.0.3](https://github.com/ash-project/ash_postgres/compare/v2.0.2...v2.0.3) (2024-05-22)

### Bug Fixes:

[updates] handle complex maps/list on update

[Ash.Query] support anonymous aggregates in sorts

[exists] ensure parent_as bindings properly reference binding names

[migration generator] add and remove custom indexes in tandem properly

### Improvements:

[references] support `on_delete: :nilify` for specific columns (#289)

## [v2.0.2](https://github.com/ash-project/ash_postgres/compare/v2.0.1...v2.0.2) (2024-05-15)

### Bug Fixes:

- [update_query/destroy_query] rework the update and destroy query builder to support multiple kinds of joining

- [mix ash_postgres.migrate] remove duplicate repo flags (#285)

- [Ash.Error.Changes.StaleRecord] ensure filter is included in stale record error messages we return

- [AshPostgres.MigrationGenerator] properly parse previous version from migration generation

## [v2.0.1](https://github.com/ash-project/ash_postgres/compare/v2.0.0...v2.0.1) (2024-05-12)

### Bug Fixes:

- [AshPostgres.MigrationGenerator] properly parse previous version of custom extensions when generating migrations

## [v2.0.0](https://github.com/ash-project/ash_postgres/compare/v2.0.0...2.0)

The changelog is starting over. Please see `/documentation/1.0-CHANGELOG.md` in GitHub for previous changelogs.

### Breaking Changes:

- [Ash.Type.UUID] change defaults in migrations for uuids to `gen_random_uuid()`
- [Ash.Type.DateTime] Use UTC for default generated timestamps (#131)
- [AshPostgres.DataLayer] must now know the min_pg_version that will be used. By default we check this at repo startup by asking the database, but you can also define it yourself.
- [AshPostgres.DataLayer] Now requires postgres version 14 or higher

### Features:

- [AshPostgres.Timestamptz] add timestamptz types (#266)
- [AshPostgres.Repo] add `create?` and `drop?` callbacks to `AshPostgres.Repo` (#143)
- [AshPostgres.DataLayer] support `c:AshDataLayer.calculate/3` capability

### Bug Fixes:

- [AshPostgres.MigrationGenerator] honor dry_run option in extension migrations
- [AshPostgres.MigrationGenerator] don't wait for shell input when checking migrations
- [AshPostgres.DataLayer] ensure limit/offset triggers joining for update/destroy query
- [AshPostgres.DataLayer] properly honor `limit` in bulk operations
- [AshPostgres.DataLayer] ensure that `exists` with a filter paired with `from_many?` functions properly

### Improvements:

- [AshPostgres.Repo] warn on missing ash-functions at compile time
- [AshPostgres.Repo] add default implementation for pg_version, and rename to `min_pg_version`
- [mix ash.rollback] support `mix ash.rollback` with interactive rollback
- [AshSql] move many internals out to `AshSql` package to be shared
