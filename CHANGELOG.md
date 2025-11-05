<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://www.conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v2.6.25](https://github.com/ash-project/ash_postgres/compare/v2.6.24...v2.6.25) (2025-11-05)




### Bug Fixes:

* add failing test for exists expansnion inside of calculations by Zach Daniel

## [v2.6.24](https://github.com/ash-project/ash_postgres/compare/v2.6.23...v2.6.24) (2025-10-30)




### Bug Fixes:

* handle results that can't be mapped to the changeset in bulk_create (#638) by Barnabas Jovanovics

* handle results that can't be mapped to the changeset in bulk_create by Barnabas Jovanovics

### Improvements:

* remove unused bulk operation metadata function & update ash by Zach Daniel

## [v2.6.23](https://github.com/ash-project/ash_postgres/compare/v2.6.22...v2.6.23) (2025-10-15)




### Improvements:

* implement combination_acc/1 by Zach Daniel

## [v2.6.22](https://github.com/ash-project/ash_postgres/compare/v2.6.21...v2.6.22) (2025-10-14)




### Bug Fixes:

* return skipped upserts in bulk_create (#626) by Barnabas Jovanovics

### Improvements:

* leverage new aggregate loading optimization by Zach Daniel

## [v2.6.21](https://github.com/ash-project/ash_postgres/compare/v2.6.20...v2.6.21) (2025-10-10)




### Bug Fixes:

* simplify bulk operation metadata handling by Zach Daniel

* update ash_postgresql to handle the new bulk_create response in Ash v3.5.44 (#632) by Daniel Gollings

* Support non-public PostgreSQL schemas in resource generator (#631) by Elliot Bowes

* guard against missing snapshot directories in migration generator by Elliot Bowes

* ensure that tenant is properly used in many-to-many joins by Zach Daniel

### Improvements:

* Add immutable version of `ash_raise_error` function to support extensions like Citus (#620) by Steve Brambilla

## [v2.6.20](https://github.com/ash-project/ash_postgres/compare/v2.6.19...v2.6.20) (2025-09-27)




### Bug Fixes:

* use `:mutate` repo for on_transaction_begin callback by Zach Daniel

### Improvements:

* location in spark errors and migration generator fixes by Zach Daniel

* use default constraint of 'now()' for AshPostgres.Timestamptz (#621) by siassaj

## [v2.6.19](https://github.com/ash-project/ash_postgres/compare/v2.6.18...v2.6.19) (2025-09-20)




### Bug Fixes:

* fix conditional on installing ash in installer by Zach Daniel

## [v2.6.18](https://github.com/ash-project/ash_postgres/compare/v2.6.17...v2.6.18) (2025-09-19)




### Bug Fixes:

* Handle optional/empty input in relationship name guesser (#616) by Trond A Ekseth

* properly handle sorts w/ parent refs on lateral joins by Zach Daniel

* annotate unrelated exists expressions as supported by Zach Daniel

## [v2.6.17](https://github.com/ash-project/ash_postgres/compare/v2.6.16...v2.6.17) (2025-08-31)




### Bug Fixes:

* resolve a typo in pending dev migration error message (#608) by Sheharyar Naseer

## [v2.6.16](https://github.com/ash-project/ash_postgres/compare/v2.6.15...v2.6.16) (2025-08-21)




### Improvements:

* Unrelated aggregates (#606) by Zach Daniel

## [v2.6.15](https://github.com/ash-project/ash_postgres/compare/v2.6.14...v2.6.15) (2025-08-07)




### Bug Fixes:

* Use new attribute source in down migration (#604) by Anatolij Werle

* always set disable_async, and remove log level config by Zach Daniel

## [v2.6.14](https://github.com/ash-project/ash_postgres/compare/v2.6.13...v2.6.14) (2025-07-29)




### Bug Fixes:

* deduplicate identity keys by Zach Daniel

## [v2.6.13](https://github.com/ash-project/ash_postgres/compare/v2.6.12...v2.6.13) (2025-07-27)




### Bug Fixes:

* ensure tenant prefix is set only for resources with context multitenancy (#600) by Emad Shaaban

## [v2.6.12](https://github.com/ash-project/ash_postgres/compare/v2.6.11...v2.6.12) (2025-07-25)




### Bug Fixes:

* ensure tenant is set on query for updates by Zach Daniel

### Improvements:

* do not create snapshots for resources that have no attributes  #571 (#599) by horberlan

## [v2.6.11](https://github.com/ash-project/ash_postgres/compare/v2.6.10...v2.6.11) (2025-07-17)




### Bug Fixes:

* clean args and properly scope rollback task by Zach Daniel

* Reverse migrations order when reverting dev migrations (#590) by Kenneth Kostrešević

### Improvements:

* make rollbacks safer by using `--to` instead of `-n` by Zach Daniel

## [v2.6.10](https://github.com/ash-project/ash_postgres/compare/v2.6.9...v2.6.10) (2025-07-09)




### Bug Fixes:

* properly return the type when configured by Zach Daniel

* retain sort when upgrading to a subquery by Zach Daniel

## [v2.6.9](https://github.com/ash-project/ash_postgres/compare/v2.6.8...v2.6.9) (2025-06-25)




### Bug Fixes:

* smallserial not mapping to proper type (#574) by Marc Planelles

* Fix foreign key constraint on specially named references (#572) by olivermt

## [v2.6.8](https://github.com/ash-project/ash_postgres/compare/v2.6.7...v2.6.8) (2025-06-18)




### Bug Fixes:

* ensure prefix is set even with create_schemas_in_migrations? false by Zach Daniel

## [v2.6.7](https://github.com/ash-project/ash_postgres/compare/v2.6.6...v2.6.7) (2025-06-13)




### Bug Fixes:

* double select error (#569) by Barnabas Jovanovics

## [v2.6.6](https://github.com/ash-project/ash_postgres/compare/v2.6.5...v2.6.6) (2025-06-10)




### Bug Fixes:

* simply storage of size/scale/precision information

## [v2.6.5](https://github.com/ash-project/ash_postgres/compare/v2.6.4...v2.6.5) (2025-06-10)




### Bug Fixes:

* remove spurios debug logging

* properly detect nested array decimals

## [v2.6.4](https://github.com/ash-project/ash_postgres/compare/v2.6.3...v2.6.4) (2025-06-09)




### Bug Fixes:

* reenable migrate task

* use `force: true`, not `force?: true` calling mix.generator

* casting integers to string in expressions works as intended (#564)

* use better wrappers around string/ci_string

### Improvements:

* add `c:AshPostgres.Repo.create_schemas_in_migrations?` callback

## [v2.6.3](https://github.com/ash-project/ash_postgres/compare/v2.6.2...v2.6.3) (2025-06-04)




### Bug Fixes:

* undo change for timestamptz usec, retaining precision

## [v2.6.2](https://github.com/ash-project/ash_postgres/compare/v2.6.1...v2.6.2) (2025-06-04)




### Bug Fixes:

* don't use `:"timestamptz(6)"` in ecto storage type

## [v2.6.1](https://github.com/ash-project/ash_postgres/compare/v2.6.0...v2.6.1) (2025-05-30)




### Bug Fixes:

* retain repo as atom in migrator task (#560)

## [v2.6.0](https://github.com/ash-project/ash_postgres/compare/v2.5.22...v2.6.0) (2025-05-30)




### Features:

* --dev flag for codegen (#555)

### Bug Fixes:

* properly encode decimal scale & preicison into snapshots

### Improvements:

* use new `PendingCodegen` error

* assume not renaming when generating dev migrations

* support scale & precision in decimal types

## [v2.5.22](https://github.com/ash-project/ash_postgres/compare/v2.5.21...v2.5.22) (2025-05-22)




### Bug Fixes:

* Convert sensitive patterns from module constant to function for OTP/28 (#552)

## [v2.5.21](https://github.com/ash-project/ash_postgres/compare/v2.5.20...v2.5.21) (2025-05-21)




### Improvements:

* update igniter, remove inflex

## [v2.5.20](https://github.com/ash-project/ash_postgres/compare/v2.5.19...v2.5.20) (2025-05-20)




### Bug Fixes:

* self-join if combination queries require more fields

* enforce tenant name rules at creation (#550)

## [v2.5.19](https://github.com/ash-project/ash_postgres/compare/v2.5.18...v2.5.19) (2025-05-06)




### Improvements:

* support unions (#543)

## [v2.5.18](https://github.com/ash-project/ash_postgres/compare/v2.5.17...v2.5.18) (2025-04-29)




### Bug Fixes:

* fix some issues in migration generator related to tenancy (#539)

* use old multitenancy in generated removals of previous indexes (#536)

* add tenant to ash bindings in update (#534)

* correct order, when renaming attribute with an identity (#533)

## [v2.5.17](https://github.com/ash-project/ash_postgres/compare/v2.5.16...v2.5.17) (2025-04-22)




### Bug Fixes:

* add tenant to ash bindings in update (#534)

* correct order, when renaming attribute with an identity (#533)

## [v2.5.16](https://github.com/ash-project/ash_postgres/compare/v2.5.15...v2.5.16) (2025-04-15)




### Bug Fixes:

* fixes for map types nested in expressions

* use proper migrations path configuration

## [v2.5.15](https://github.com/ash-project/ash_postgres/compare/v2.5.14...v2.5.15) (2025-04-09)




### Bug Fixes:

* ash postgres subquery usage (#524)

* use subqueries for join resources

* use schema when changing reference deferrability (#519)

### Improvements:

* propagate `-r` flag to Ecto (#521)

## [v2.5.14](https://github.com/ash-project/ash_postgres/compare/v2.5.13...v2.5.14) (2025-03-28)




### Bug Fixes:

* remove debugging code accidentally committed

* retain loads on atomic upgrade update actions

### Improvements:

* create schema before table creation (#518)

## [v2.5.13](https://github.com/ash-project/ash_postgres/compare/v2.5.12...v2.5.13) (2025-03-25)




### Bug Fixes:

* order when renaming attribute with an index (#514)

## [v2.5.12](https://github.com/ash-project/ash_postgres/compare/v2.5.11...v2.5.12) (2025-03-18)




### Improvements:

* include error detail in constraint violation errors

## [v2.5.11](https://github.com/ash-project/ash_postgres/compare/v2.5.10...v2.5.11) (2025-03-11)




### Bug Fixes:

* ignore attributes with no known type

* honor skip_unknown option in spec table generator

* honor --no-migrations flag

* allow optional input for relationship name guesser

* put move up/down in the right place

* go to top of if block

* use `configures_key?/3`

* don't modify repo in runtime.exs

* remove Helpdesk.Repo from installer ð¤¦

* only configure repo in installer if not already configured

* install ash if not installed already

### Improvements:

* document options, add `--no-migrations`

* add `skip_unknown` option to `ash_postgres.gen.resources`

## [v2.5.10](https://github.com/ash-project/ash_postgres/compare/v2.5.9...v2.5.10) (2025-03-06)




### Bug Fixes:

* honor skip_tables

### Improvements:

* never import `schema_migrations` table

## [v2.5.9](https://github.com/ash-project/ash_postgres/compare/v2.5.8...v2.5.9) (2025-03-06)




### Bug Fixes:

* match on non-empty repo options

### Improvements:

* add `--public` option to `gen.resources`, default `true`

* add `--default-actions` option to `gen.resources`, default `true`

## [v2.5.8](https://github.com/ash-project/ash_postgres/compare/v2.5.7...v2.5.8) (2025-03-06)




### Bug Fixes:

* handle CLI args better for ash_postgres.gen.resources

* compose check constraints and base filters properly

## [v2.5.7](https://github.com/ash-project/ash_postgres/compare/v2.5.6...v2.5.7) (2025-03-04)




### Bug Fixes:

* handle errors from identities in polymorphic resources properly (#497)

* Use exclusion_constraint instead of check_constraint in add_exclusion_constraints (#495)

* check for stale record errors on destroy

* don't rely on private function from `Ecto.Repo` (#492)

## [v2.5.6](https://github.com/ash-project/ash_postgres/compare/v2.5.5...v2.5.6) (2025-02-25)




### Bug Fixes:

* start lateral join source query bindings at 500

* Ensure primary key migrations use prefix for multitenancy (#488)

* don't rewrite identities when only global? is changed

* don't modify an attribute when it only needs to be renamed

### Improvements:

* support SKIP LOCKED in locks

## [v2.5.5](https://github.com/ash-project/ash_postgres/compare/v2.5.4...v2.5.5) (2025-02-17)




### Bug Fixes:

* ensure field names defaults to the field of the constraint

## [v2.5.4](https://github.com/ash-project/ash_postgres/compare/v2.5.3...v2.5.4) (2025-02-17)




### Improvements:

* Add support for field names in idenitity constraints (#478)

## [v2.5.3](https://github.com/ash-project/ash_postgres/compare/v2.5.2...v2.5.3) (2025-02-14)




### Bug Fixes:

* handle dropping primary key columns properly

* Ignore module conflict when compiling migration file (#482)

## [v2.5.2](https://github.com/ash-project/ash_postgres/compare/v2.5.1...v2.5.2) (2025-02-11)




### Bug Fixes:

* update lateral join logic to match ash_sql's

* simplify lateral join source filter

* update sql log switches for migration and rollback tasks (#470)

### Improvements:

* add vector l2 distance function

* use dimenstions constraint on vector for size

* consider identity.where in identity deduplicator

* generate migrations task support concurrent indexes flag (#471)

## [v2.5.1](https://github.com/ash-project/ash_postgres/compare/v2.5.0...v2.5.1) (2025-01-27)




### Bug Fixes:

* handle cross global to tenant references in migration generator

## [v2.5.0](https://github.com/ash-project/ash_postgres/compare/v2.4.22...v2.5.0) (2025-01-20)




### Features:

* add repo callback to disable atomic actions and error expressions (#464)

### Bug Fixes:

* generate a repo when selecting one

* handle regex match correctly (#460)

### Improvements:

* use prettier SQL in `Ash.calculate`

* add `c:AshPostgres.Repo.default_constraint_match_type`

* mark ash_raise_error as STABLE

## [v2.4.22](https://github.com/ash-project/ash_postgres/compare/v2.4.21...v2.4.22) (2025-01-13)




### Bug Fixes:

* inner join bulk operations if distinct? is present

* fully specificy synthesized indices from multi-resource tables

## [v2.4.21](https://github.com/ash-project/ash_postgres/compare/v2.4.20...v2.4.21) (2025-01-06)




### Bug Fixes:

* filter query by source record ids when lateral joining

* don't use symlinked app dir for migration's path

## [v2.4.20](https://github.com/ash-project/ash_postgres/compare/v2.4.19...v2.4.20) (2024-12-26)




### Bug Fixes:

* use passed in version of postgres when modifying existing repo

## [v2.4.19](https://github.com/ash-project/ash_postgres/compare/v2.4.18...v2.4.19) (2024-12-26)




### Bug Fixes:

* ensure there is always at least one upsert field so filter is run

### Improvements:

* better min_pg_version when modifying a repo

* automatically set `min_pg_version` where possible

* use a notice to suggest configuring `min_pg_version`

## [v2.4.18](https://github.com/ash-project/ash_postgres/compare/v2.4.17...v2.4.18) (2024-12-20)




### Bug Fixes:

* handle double select issue

### Improvements:

* make igniter optional

* make tsvector type selectable

## [v2.4.17](https://github.com/ash-project/ash_postgres/compare/v2.4.16...v2.4.17) (2024-12-16)




### Bug Fixes:

* Fix query for metadata on foreign keys and fix duplicate references being produced (#444)

* alter resource generation query to go to the source pg_constraints table instead of to the view to fetch constraint data (#443)

## [v2.4.16](https://github.com/ash-project/ash_postgres/compare/v2.4.15...v2.4.16) (2024-12-12)




### Bug Fixes:

* properly support expr errors in bulk create

* only build references for belongs_to relationships

### Improvements:

* add postgres_reference_expr callback (#438)

## [v2.4.15](https://github.com/ash-project/ash_postgres/compare/v2.4.14...v2.4.15) (2024-12-06)




### Bug Fixes:

* split off varchar options from index

* don't attempt to use non-existent relationship

* handle manual/no_attributes? relationships in lateral join logic

* don't use `priv` configuration for snapshot_path

### Improvements:

* update sql implementation for type determination

## [v2.4.14](https://github.com/ash-project/ash_postgres/compare/v2.4.13...v2.4.14) (2024-11-27)




### Bug Fixes:

* pass AST to deal with stupid igniter behavior

## [v2.4.13](https://github.com/ash-project/ash_postgres/compare/v2.4.12...v2.4.13) (2024-11-26)

### Bug Fixes:

- [`mix ash.migrate`] honor the `snapshots_only` option

### Improvements:

- [`mix ash.migrate`] honor repo configuration in migration generator

- [`mix ash.codegen`] honor `:priv` in migration generator, and make it explicitly configurable

- [`mix ash_postgres.install`] don't generate task aliases that run seeds in test

## [v2.4.12](https://github.com/ash-project/ash_postgres/compare/v2.4.11...v2.4.12) (2024-10-30)

### Bug Fixes:

- [query builder] don't double add distinct clauses

- [`AshPostgres.DataLayer`] don't use `cast` for changes

### Improvements:

- [`AshPostgres.Repo`] set `prefer_transaction?` to false in generated repos

- [`AshPostgres.DataLayer`] support prefer_transaction?

## [v2.4.11](https://github.com/ash-project/ash_postgres/compare/v2.4.10...v2.4.11) (2024-10-23)

### Bug Fixes:

- [upserts] ensure repo_opts is passed through to `repo.all/2`

## [v2.4.10](https://github.com/ash-project/ash_postgres/compare/v2.4.9...v2.4.10) (2024-10-23)

## Security

- Patch of [GHSA-hf59-7rwq-785m](https://github.com/ash-project/ash_postgres/security/advisories/GHSA-hf59-7rwq-785m) Empty, atomic, non-bulk actions, policy bypass for side-effects vulnerability.

### Bug Fixes:

- [upserts] run any query that could produce errors when performing atomic upgrade

- [multitenant migrations] race condition compiling migrations when concurrently creating new tenants (#406)

## [v2.4.9](https://github.com/ash-project/ash_postgres/compare/v2.4.8...v2.4.9) (2024-10-16)

### Bug Fixes:

- [`mix ash_postgres.gen.resources`] fix resource generator task & tests

## [v2.4.8](https://github.com/ash-project/ash_postgres/compare/v2.4.7...v2.4.8) (2024-10-11)

### Improvements:

- [migration generator] use the `name` parameter when generating migrations

## [v2.4.7](https://github.com/ash-project/ash_postgres/compare/v2.4.6...v2.4.7) (2024-10-10)

### Improvements:

- [upserts] adapt to fixes and optimizations around skipped upserts in ash core

## [v2.4.6](https://github.com/ash-project/ash_postgres/compare/v2.4.5...v2.4.6) (2024-10-07)

### Improvements:

- [`mix ash_postgres.install`] with `--yes` assume oldest version

## [v2.4.5](https://github.com/ash-project/ash_postgres/compare/v2.4.4...v2.4.5) (2024-10-06)

### Bug Fixes:

- [upserts] ensure upsert fields are uniq

### Improvements:

- [`mix ash_postgres.install`] detect 1 arg repo use in installer

- [`AshPostgres.Repo`] support to_ecto(%Ecto.Changeset{}) and from_ecto(%Ecto.Changeset{}) (#395)

## [v2.4.4](https://github.com/ash-project/ash_postgres/compare/v2.4.3...v2.4.4) (2024-09-29)

### Bug Fixes:

- [atomic updates] handle atomic array operations

## [v2.4.3](https://github.com/ash-project/ash_postgres/compare/v2.4.2...v2.4.3) (2024-09-27)

### Bug Fixes:

- [`mix ash_postgres.gen.resources`] support pg <= 14 in resource generator, and update tests

## [v2.4.2](https://github.com/ash-project/ash_postgres/compare/v2.4.1...v2.4.2) (2024-09-24)

### Bug Fixes:

- [migration generator] typo of `biging` -> `bigint`

- [migration generator] altering attributes not properly generating foreign keys in some cases

- [`mix ash_postres.install`] use correct module name in the `DataCase` moduledocs. (#393)

- [migration generator] trim input before passing to `String.to_integer/1`. (#389)

### Improvements:

- [`mix ash_postgres.install`] add `--repo` option to installer, and warn on clashing existing repo

- [`mix ash_postgres.install`] prompt for minimum pg version

- [`mix ash_postgres.install`] adjust mix task aliases to be used with `ash_postgres`

- [migration generator] set a name for generated migrations

## [v2.4.1](https://github.com/ash-project/ash_postgres/compare/v2.4.0...v2.4.1) (2024-09-16)

### Bug Fixes:

- [bulk updates] ensure that returning is never an empty list

- [`mix ash_postgres.gen.resources`] match on table schema as well as table name

## [v2.4.0](https://github.com/ash-project/ash_postgres/compare/v2.3.1...v2.4.0) (2024-09-13)

### Features:

- [`AshPostgres.Ltree`] Implement Ltree Type (#385)

### Improvements:

- [migration generator] remove LEAKPROOF from function to prevent migration issues

- [`Ash.Changeset`] support upcoming `action_select` options

- [`mix ash.install`] ensure `Repo` is started after telemetry in igniter installer

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

## v2.1.17 (2024-07-27)

### Improvements:

- [`ash_sql`] update ash & ash_sql for various fixes

## v2.1.16 (2024-07-25)

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

## v2.1.8 (2024-07-17)

### Bug Fixes:

- [aggregates] update ash_sql & ash for include_nil? fix (and test it)

- [aggregates] ensure synthesized query aggregates have context set

### Improvements:

- [installers] update igniter dependencies

- [expressions] add `binding()` expression, for referring to the current table

## v2.1.7 (2024-07-17)

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

## v2.1.1 (2024-07-10)

### Bug Fixes:

- [mix ash_postgres.install] properly interpolate module names in installer

## v2.1.0 (2024-07-10)

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

## v2.0.7 (2024-06-06)

### Bug Fixes:

- [fix] update ash_sql and fix issues retaining lateral join context

- [fix] ensure that all current attribute values are selected on bulk update shifted root query

## v2.0.6 (2024-05-29)

### Bug Fixes:

- [atomic updates] properly support aggregate references in atomic updates

- [migration generator] ensure that identities are dropped when where/nils_distinct? are changed

- [migration generator] ensure that `where` is wrapped in parenthesis

- [ecto compatibility] support old/new parameterized type format

### Improvements:

- [identities] require clarification of index names > 63 characters

- [mix ash_postgres.squash_snapshots] add `ash_postgres.squash_snapshots` mix task (#302)

## v2.0.5 (2024-05-24)

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

## v2.0.1 (2024-05-12)

### Bug Fixes:

- [AshPostgres.MigrationGenerator] properly parse previous version of custom extensions when generating migrations

## v2.0.0

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
