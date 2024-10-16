# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v2.4.9](https://github.com/ash-project/ash_postgres/compare/v2.4.8...v2.4.9) (2024-10-16)




### Bug Fixes:

* fix resource generator task & tests

## [v2.4.8](https://github.com/ash-project/ash_postgres/compare/v2.4.7...v2.4.8) (2024-10-11)




### Improvements:

* use the `name` parameter when generating migrations

## [v2.4.7](https://github.com/ash-project/ash_postgres/compare/v2.4.6...v2.4.7) (2024-10-10)




### Improvements:

* adapt to fixes and optimizations around skipped upserts in ash core

## [v2.4.6](https://github.com/ash-project/ash_postgres/compare/v2.4.5...v2.4.6) (2024-10-07)




### Improvements:

* with `--yes` assume oldest version

## [v2.4.5](https://github.com/ash-project/ash_postgres/compare/v2.4.4...v2.4.5) (2024-10-06)




### Bug Fixes:

* ensure upsert fields are uniq

### Improvements:

* detect 1 arg repo use in installer

* support to_ecto(%Ecto.Changeset{}) and from_ecto(%Ecto.Changeset{}) (#395)

## [v2.4.4](https://github.com/ash-project/ash_postgres/compare/v2.4.3...v2.4.4) (2024-09-29)




### Bug Fixes:

* handle atomic array operations

## [v2.4.3](https://github.com/ash-project/ash_postgres/compare/v2.4.2...v2.4.3) (2024-09-27)




### Bug Fixes:

* support pg <= 14 in resource generator, and update tests

## [v2.4.2](https://github.com/ash-project/ash_postgres/compare/v2.4.1...v2.4.2) (2024-09-24)




### Bug Fixes:

* typo of `biging` -> `bigint`

* altering attributes not properly generating foreign keys in some cases

* installer: use correct module name in the `DataCase` moduledocs. (#393)

* trim input before passing to `String.to_integer/1`. (#389)

### Improvements:

* add `--repo` option to installer, and warn on clashing existing repo

* prompt for minimum pg version

* adjust mix task aliases to be used with `ash_postgres`

* set a name for generated migrations

## [v2.4.1](https://github.com/ash-project/ash_postgres/compare/v2.4.0...v2.4.1) (2024-09-16)




### Bug Fixes:

* ensure that returning is not an empty list

* match on table schema as well as table name

## [v2.4.0](https://github.com/ash-project/ash_postgres/compare/v2.3.1...v2.4.0) (2024-09-13)

### Features:

- Implement Ltree Type (#385)

### Improvements:

- update ash to latest version

- remove LEAKPROOF from function to prevent migration issues

- support upcoming `action_select` options

- ensure `Repo` is started after telemetry in igniter installer

- update to latest igniter functions

## [v2.3.1](https://github.com/ash-project/ash_postgres/compare/v2.3.0...v2.3.1) (2024-09-05)

### Improvements:

- [`mix ash_postgres.gen.migrations`] better imported index names

- [`mix ash_postgres.gen.migrations`] add `--extend` option, forwarded to generated resource

## [v2.3.0](https://github.com/ash-project/ash_postgres/compare/v2.2.5...v2.3.0) (2024-09-05)

### Features:

- [`mix ash_postgres.gen.resources`] Add `mix ash_postgres.gen.resources` for importing tables from an existing database as resources

## [v2.2.5](https://github.com/ash-project/ash_postgres/compare/v2.2.4...v2.2.5) (2024-09-04)

### Improvements:

- [`AshPostgres.DataLayer`] support ash main upsert_condition logic

## [v2.2.4](https://github.com/ash-project/ash_postgres/compare/v2.2.3...v2.2.4) (2024-09-03)

### Bug Fixes:

- [`AshPostgres.DataLayer`] ensure default bindings are present on data layer

- [`AshPostgres.DataLayer`] properly traverse newtypes when determining types

## [v2.2.3](https://github.com/ash-project/ash_postgres/compare/v2.2.2...v2.2.3) (2024-08-18)

### Bug Fixes:

- [`mix ash_postgres.install`] was not adding ash_functions/min_pg_version

## [v2.2.2](https://github.com/ash-project/ash_postgres/compare/v2.2.1...v2.2.2) (2024-08-17)

### Bug Fixes:

- [`mix ash_postgres.install`] properly handle new igniter installer functions

## [v2.2.1](https://github.com/ash-project/ash_postgres/compare/v2.2.0...v2.2.1) (2024-08-16)

### Bug Fixes:

- [`AshPostgres.DataLayer`] set a proper default for `skip_unique_indexes`

### Improvements:

- [`mix ash_postgres.install`] include `min_pg_version` in new generators

## [v2.2.0](https://github.com/ash-project/ash_postgres/compare/v2.1.19...v2.2.0) (2024-08-13)

### Bug Fixes:

- [`AshPostgres.Repo`] remove `Agent` "convenience" for determining min pg version

We need to require that users provide this function. To that end we're
adding a warning in a minor release branch telling users to define this.
The agent was acting as a bottleneck that all queries must go through,
causing nontrivial performance issues at scale.

- [upserts] handle filter condition on create (#368)

## [v2.1.19](https://github.com/ash-project/ash_postgres/compare/v2.1.18...v2.1.19) (2024-08-12)

### Bug Fixes:

- [ecto compatibility] we missed a change when preparing for ecto 3.12 parameterized type changes

- [exists aggregates] update ash_sql for exists aggregate fixes

## [v2.1.18](https://github.com/ash-project/ash_postgres/compare/v2.1.17...v2.1.18) (2024-08-09)

### Improvements:

- [`ash_postgres.gen.migration`] dynamically select and allow setting a repo

## [v2.1.17](https://github.com/ash-project/ash_postgres/compare/v2.1.16...v2.1.17) (2024-07-27)

### Improvements:

- [`ash_sql`] update ash & ash_sql for various fixes

## [v2.1.16](https://github.com/ash-project/ash_postgres/compare/v2.1.15...v2.1.16) (2024-07-25)

### Bug Fixes:

- [updates] don't overwrite non-updated fields on update

- [`mix ash_postgres.generate_migrations`] ensure app is compiled before using repo modules

### Improvements:

- [`ash_sql`] update ash_sql for cleaner queries

## [v2.1.15](https://github.com/ash-project/ash_postgres/compare/v2.1.14...v2.1.15) (2024-07-23)

### Bug Fixes:

- [query building] use a subquery if any exists aggregates are in play

## [v2.1.14](https://github.com/ash-project/ash_postgres/compare/v2.1.13...v2.1.14) (2024-07-22)

### Bug Fixes:

- [multitenancy] properly convert tenant to string when building lateral join

## [v2.1.13](https://github.com/ash-project/ash_postgres/compare/v2.1.12...v2.1.13) (2024-07-22)

### Bug Fixes:

- [atomic validations] update ash & ash_sql for fixes, test atomic validations in destroys

## [v2.1.12](https://github.com/ash-project/ash_postgres/compare/v2.1.11...v2.1.12) (2024-07-19)

### Bug Fixes:

- [`mix ash_postgres.install`] properly add prod config in installer

### Bug Fixes:

- [`mix ash_postgres.install`] properly perform or don't perform configuration modification code

- [`has_many` relationships] allow non-unique has_many source_attributes (#355)

### Improvements:

- [`mix ash_postgres.install`] prepend `:postgres` to section order

- [`mix ash.patch.extend`] pluralize table name in extender

## [v2.1.10](https://github.com/ash-project/ash_postgres/compare/v2.1.9...v2.1.10) (2024-07-18)

### Bug Fixes:

- [lateral joins] allow non-unique has_many source_attributes (#355)

## [v2.1.9](https://github.com/ash-project/ash_postgres/compare/v2.1.8...v2.1.9) (2024-07-18)

### Bug Fixes:

### Improvements:

- [`mix ash.gen.resource`] pluralize table name in extender

## [v2.1.8](https://github.com/ash-project/ash_postgres/compare/v2.1.7...v2.1.8) (2024-07-17)

### Bug Fixes:

- [aggregates] update ash_sql & ash for include_nil? fix (and test it)

- [aggregates] ensure synthesized query aggregates have context set

### Improvements:

- [installers] update igniter dependencies

- [expressions] add `binding()` expression, for referring to the current table

## [v2.1.7](https://github.com/ash-project/ash_postgres/compare/v2.1.6...v2.1.7) (2024-07-17)

### Bug Fixes:

- update to latest ash version for aggregate fix

- update ash_sql for include_nil? fix and test it

- ensure synthesized query aggregates have context set

### Improvements:

- update ash/igniter dependencies

- add `binding()` expression

- use latest type casting code from ash

- support new type determination code

## [v2.1.6](https://github.com/ash-project/ash_postgres/compare/v2.1.5...v2.1.6) (2024-07-16)

### Bug Fixes:

- ensure synthesized query aggregates have context set

### Improvements:

- update ash/igniter dependencies

- add `binding()` expression

- use latest type casting code from ash

- support new type determination code

## [v2.1.5](https://github.com/ash-project/ash_postgres/compare/v2.1.4...v2.1.5) (2024-07-15)

### Bug Fixes:

- ensure synthesized query aggregates have context set

### Improvements:

- [`Ash.Expr`] add `binding()` expression to refer to current table

- [`Ash.Expr`] use latest type casting code from ash

## [v2.1.4](https://github.com/ash-project/ash_postgres/compare/v2.1.3...v2.1.4) (2024-07-14)

### Improvements:

- [`Ash.Expr`] use latest type casting code from ash

## [v2.1.3](https://github.com/ash-project/ash_postgres/compare/v2.1.2...v2.1.3) (2024-07-14)

### Improvements:

- [`Ash.Expr`] support new type determination code

## [v2.1.2](https://github.com/ash-project/ash_postgres/compare/v2.1.1...v2.1.2) (2024-07-13)

- [query builder] update ash & improve type casting behavior

## [v2.1.1](https://github.com/ash-project/ash_postgres/compare/v2.1.0...v2.1.1) (2024-07-10)

### Bug Fixes:

- [mix ash_postgres.install] properly interpolate module names in installer

## [v2.1.0](https://github.com/ash-project/ash_postgres/compare/v2.0.12...v2.1.0) (2024-07-10)

### Features:

- [AshPostgres.DataLayer] add `storage_types` configuration (#342)
- [generators] add `mix ash_postgres.install` (`mix igniter.install ash_postgres`)

### Bug Fixes:

- [AshPostgres.DataLayer] ensure that `from_many?` relationships in lateral join have a limit applied

- [migration generator] properly delete args passed from migrate to ecto

### Improvements:

- [Ash.Type.UUIDv7] add support for `:uuid_v7` type (#333)

- [migration generator] order keys in snapshot json (#339)

## [v2.0.12](https://github.com/ash-project/ash_postgres/compare/v2.0.11...v2.0.12) (2024-06-20)

### Bug Fixes:

- [migration generator] only add references indexes if they've changed

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
