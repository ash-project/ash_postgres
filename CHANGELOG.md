# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.35.5](https://github.com/ash-project/ash_postgres/compare/v0.35.4...v0.35.5) (2021-03-29)




### Bug Fixes:

* Made AshPostgres.Repo.init/2 overridable (#51)

### Improvements:

* only count resources w/ create action for nullability

* better error message on missing table

## [v0.35.4](https://github.com/ash-project/ash_postgres/compare/v0.35.3...v0.35.4) (2021-03-21)




### Bug Fixes:

* reroute `Ash.Type.UUID` to `:uuid` in migrations

* force create extensions snapshot

### Improvements:

* consistent foreign key names

* support custom foreign key error messages

## [v0.35.3](https://github.com/ash-project/ash_postgres/compare/v0.35.2...v0.35.3) (2021-03-19)




### Bug Fixes:

* force create extensions snapshot

* more conservative inner join checks

* add back in inner join detection logic

### Improvements:

* consistent foreign key names

* support custom foreign key error messages

## [v0.35.2](https://github.com/ash-project/ash_postgres/compare/v0.35.1...v0.35.2) (2021-03-05)




### Bug Fixes:

* more conservative inner join checks

* add back in inner join detection logic

## [v0.35.1](https://github.com/ash-project/ash_postgres/compare/v0.35.0...v0.35.1) (2021-03-02)




### Bug Fixes:

* don't start the whole app in migrate

## [v0.35.0](https://github.com/ash-project/ash_postgres/compare/v0.34.7...v0.35.0) (2021-03-02)




### Features:

* automatically install extensions from repo

## [v0.34.7](https://github.com/ash-project/ash_postgres/compare/v0.34.6...v0.34.7) (2021-03-02)




### Bug Fixes:

* typo in references for multitenancy

* `null: true` when attr isn't on all resources for a table

## [v0.34.6](https://github.com/ash-project/ash_postgres/compare/v0.34.5...v0.34.6) (2021-02-24)




### Bug Fixes:

* better embedded filters, switch to latest ash

## [v0.34.5](https://github.com/ash-project/ash_postgres/compare/v0.34.4...v0.34.5) (2021-02-23)




### Improvements:

* support latest ash

## [v0.34.4](https://github.com/ash-project/ash_postgres/compare/v0.34.3...v0.34.4) (2021-02-08)




### Bug Fixes:

* trim when choosing new attribute name

## [v0.34.3](https://github.com/ash-project/ash_postgres/compare/v0.34.2...v0.34.3) (2021-02-06)




### Bug Fixes:

* don't reference polymorphic tables to belongs_to relationships

## [v0.34.2](https://github.com/ash-project/ash_postgres/compare/v0.34.1...v0.34.2) (2021-02-06)




### Bug Fixes:

* set up references properly

## [v0.34.1](https://github.com/ash-project/ash_postgres/compare/v0.34.0...v0.34.1) (2021-02-06)




### Bug Fixes:

* reference the configured table if set

## [v0.34.0](https://github.com/ash-project/ash_postgres/compare/v0.33.1...v0.34.0) (2021-02-06)




### Features:

* support polymorphic relationships

## [v0.33.1](https://github.com/ash-project/ash_postgres/compare/v0.33.0...v0.33.1) (2021-01-27)




### Bug Fixes:

* actually insert the tracking row

## [v0.33.0](https://github.com/ash-project/ash_postgres/compare/v0.32.2...v0.33.0) (2021-01-27)




### Features:

* add `mix ash_postgres.create`

* add `mix ash_postgres.migrate`

* add `mix ash_postgres.migrate --tenants`

* add `mix ash_postgres.drop`

### Bug Fixes:

* rework the way multitenant migrations work

## [v0.32.2](https://github.com/ash-project/ash_postgres/compare/v0.32.1...v0.32.2) (2021-01-26)




### Bug Fixes:

* un-break the `in` filter type casting code

### Improvements:

* better errors for multitenant unique constraints

## [v0.32.1](https://github.com/ash-project/ash_postgres/compare/v0.32.0...v0.32.1) (2021-01-24)




### Bug Fixes:

* `ago` was adding, not subtracting

## [v0.32.0](https://github.com/ash-project/ash_postgres/compare/v0.31.1...v0.32.0) (2021-01-24)




### Features:

* support latest ash + contains

## [v0.31.1](https://github.com/ash-project/ash_postgres/compare/v0.31.0...v0.31.1) (2021-01-22)




### Improvements:

* update to latest ash

## [v0.31.0](https://github.com/ash-project/ash_postgres/compare/v0.30.1...v0.31.0) (2021-01-22)




### Features:

* support fragments

* support type casting

* update to latest ash to support expressions

### Bug Fixes:

* update CI versions

## [v0.30.1](https://github.com/ash-project/ash_postgres/compare/v0.30.0...v0.30.1) (2021-01-13)




## [v0.30.0](https://github.com/ash-project/ash_postgres/compare/v0.29.6...v0.30.0) (2021-01-13)




### Features:

* Add check_migrated option to migration generator (#40) (#43)

## [v0.29.6](https://github.com/ash-project/ash_postgres/compare/v0.29.5...v0.29.6) (2021-01-12)




### Bug Fixes:

* rename out of phase, small migration fix

## [v0.29.5](https://github.com/ash-project/ash_postgres/compare/v0.29.4...v0.29.5) (2021-01-10)




### Improvements:

* Use ecto_sql formatter settings (#38)

## [v0.29.4](https://github.com/ash-project/ash_postgres/compare/v0.29.3...v0.29.4) (2021-01-10)




### Improvements:

* Omit field opts if they are default values (#37)

## [v0.29.3](https://github.com/ash-project/ash_postgres/compare/v0.29.2...v0.29.3) (2021-01-08)




### Improvements:

* support latest ash

## [v0.29.2](https://github.com/ash-project/ash_postgres/compare/v0.29.1...v0.29.2) (2021-01-08)




### Improvements:

* Make integer serial if generated

## [v0.29.1](https://github.com/ash-project/ash_postgres/compare/v0.29.0...v0.29.1) (2021-01-08)




### Improvements:

* support latest ash version

## [v0.29.0](https://github.com/ash-project/ash_postgres/compare/v0.28.1...v0.29.0) (2021-01-08)




### Features:

* retain snapshot history

### Improvements:

* support latest ash version

## [v0.28.1](https://github.com/ash-project/ash_postgres/compare/v0.28.0...v0.28.1) (2021-01-07)




### Improvements:

* Add :binary migration type (#33)

## [v0.28.0](https://github.com/ash-project/ash_postgres/compare/v0.27.0...v0.28.0) (2020-12-29)




### Features:

* support latest Ash version

## [v0.27.0](https://github.com/ash-project/ash_postgres/compare/v0.26.2...v0.27.0) (2020-12-23)




### Features:

* support refs on both sides of operators

### Bug Fixes:

* bump ash version

## [v0.26.2](https://github.com/ash-project/ash_postgres/compare/v0.26.1...v0.26.2) (2020-12-06)




### Bug Fixes:

* properly accept the `tenant_migration_path`

## [v0.26.1](https://github.com/ash-project/ash_postgres/compare/v0.26.0...v0.26.1) (2020-12-01)




### Bug Fixes:

* set default properly when modifying

## [v0.26.0](https://github.com/ash-project/ash_postgres/compare/v0.25.5...v0.26.0) (2020-11-25)




### Features:

* don't drop columns unless explicitly told to

### Bug Fixes:

* various migration generator bug fixes

## [v0.25.5](https://github.com/ash-project/ash_postgres/compare/v0.25.4...v0.25.5) (2020-11-17)




### Bug Fixes:

* drop constraints outside of phases (#29)

## [v0.25.4](https://github.com/ash-project/ash_postgres/compare/v0.25.3...v0.25.4) (2020-11-07)




### Bug Fixes:

* only alter the things that have changed

## [v0.25.3](https://github.com/ash-project/ash_postgres/compare/v0.25.2...v0.25.3) (2020-11-06)




### Improvements:

* add utc_datetime migration type

## [v0.25.2](https://github.com/ash-project/ash_postgres/compare/v0.25.1...v0.25.2) (2020-11-03)




### Bug Fixes:

* access data_layer_query with function

## [v0.25.1](https://github.com/ash-project/ash_postgres/compare/v0.25.0...v0.25.1) (2020-10-29)




### Improvements:

* mark repo as not requiring compile-time dep

## [v0.25.0](https://github.com/ash-project/ash_postgres/compare/v0.24.0...v0.25.0) (2020-10-29)




### Features:

* multitenancy (#25)

### Bug Fixes:

* verify repo using ensure_compiled

## [v0.24.0](https://github.com/ash-project/ash_postgres/compare/v0.23.2...v0.24.0) (2020-10-17)




### Features:

* support latest ash

## [v0.23.2](https://github.com/ash-project/ash_postgres/compare/v0.23.1...v0.23.2) (2020-10-07)




## [v0.23.1](https://github.com/ash-project/ash_postgres/compare/v0.23.0...v0.23.1) (2020-10-06)




## [v0.23.0](https://github.com/ash-project/ash_postgres/compare/v0.22.1...v0.23.0) (2020-10-06)




### Features:

* update to latest ash, trigram filter

## [v0.22.1](https://github.com/ash-project/ash_postgres/compare/v0.22.0...v0.22.1) (2020-10-01)




### Bug Fixes:

* don't group alters with creates (#22)

* add jason dependency, clean lockfile (#21)

## [v0.22.0](https://github.com/ash-project/ash_postgres/compare/v0.21.0...v0.22.0) (2020-09-24)




### Features:

* fix error when filtering with `true`

### Bug Fixes:

* broken types for `in` operator

## [v0.21.0](https://github.com/ash-project/ash_postgres/compare/v0.20.1...v0.21.0) (2020-09-19)




### Features:

* support base_filter (#18)

## [v0.20.1](https://github.com/ash-project/ash_postgres/compare/v0.20.0...v0.20.1) (2020-09-11)




### Bug Fixes:

* document/update migration path logic

## [v0.20.0](https://github.com/ash-project/ash_postgres/compare/v0.19.0...v0.20.0) (2020-09-11)




### Features:

* snapshot-based migration generator

## [v0.19.0](https://github.com/ash-project/ash_postgres/compare/v0.18.0...v0.19.0) (2020-09-02)

### Features:

- support inner joins when possible (#15)

### Bug Fixes:

- better support for aggregates/calculations when delegating

- don't fail w/ no extensions configured

## [v0.18.0](https://github.com/ash-project/ash_postgres/compare/v0.17.0...v0.18.0) (2020-08-26)

### Features:

- update to ash 1.11 (#13)

- support Ash v1.10 (#12)

- support latest ash

- update to latest ash

## [v0.17.0](https://github.com/ash-project/ash_postgres/compare/v0.16.1...v0.17.0) (2020-08-26)

### Features:

- update to ash 1.11 (#13)

- support Ash v1.10 (#12)

- support latest ash

- update to latest ash

## [v0.16.1](https://github.com/ash-project/ash_postgres/compare/v0.16.0...v0.16.1) (2020-08-19)

### Bug Fixes:

- fix compile/dialyzer issues

## [v0.16.0](https://github.com/ash-project/ash_postgres/compare/v0.15.0...v0.16.0) (2020-08-19)

### Features:

- update to latest ash

- update to latest version of ash

## [v0.15.0](https://github.com/ash-project/ash_postgres/compare/v0.14.0...v0.15.0) (2020-08-18)

### Features:

- update to latest version of ash

## [v0.14.0](https://github.com/ash-project/ash_postgres/compare/v0.13.0...v0.14.0) (2020-08-17)

### Features:

- support ash 1.7

- support named aggregates

## [v0.13.0](https://github.com/ash-project/ash_postgres/compare/v0.12.1...v0.13.0) (2020-07-25)

### Features:

- update to latest ash

- support latest ash

## [v0.12.1](https://github.com/ash-project/ash_postgres/compare/v0.12.0...v0.12.1) (2020-07-24)

### Bug Fixes:

- add can? for `:aggregate`

## [v0.12.0](https://github.com/ash-project/ash_postgres/compare/0.11.2...v0.12.0) (2020-07-24)

### Features:

- update to latest ash

## [v0.11.2](https://github.com/ash-project/ash_postgres/compare/0.11.1...v0.11.2) (2020-07-23)

### Bug Fixes:

## [v0.11.1](https://github.com/ash-project/ash_postgres/compare/0.11.0...v0.11.1) (2020-07-23)

### Bug Fixes:

## [v0.11.0](https://github.com/ash-project/ash_postgres/compare/0.10.0...v0.11.0) (2020-07-23)

### Features:

- support ash 13.0 aggregates

## [v0.10.0](https://github.com/ash-project/ash_postgres/compare/0.9.0...v0.10.0) (2020-07-15)

### Features:

- update to latest ash

## [v0.9.0](https://github.com/ash-project/ash_postgres/compare/0.8.0...v0.9.0) (2020-07-13)

### Features:

- update to latest ash

## [v0.8.0](https://github.com/ash-project/ash_postgres/compare/0.7.0...v0.8.0) (2020-07-09)

### Features:

- update to latest ash

## [v0.7.0](https://github.com/ash-project/ash_postgres/compare/0.6.0...v0.7.0) (2020-07-09)

### Features:

- update to latest ash

- update to latest ash, add docs

- update to ash 0.9.1 for transactions

## [v0.6.0](https://github.com/ash-project/ash_postgres/compare/0.5.0...v0.6.0) (2020-06-29)

### Features:

- update to latest ash

## [v0.5.0](https://github.com/ash-project/ash_postgres/compare/0.4.0...v0.5.0) (2020-06-29)

### Features:

- upgrade to latest ash

## [v0.4.0](https://github.com/ash-project/ash_postgres/compare/0.3.0...v0.4.0) (2020-06-27)

### Features:

- update to latest ash

## [v0.3.0](https://github.com/ash-project/ash_postgres/compare/0.2.1...v0.3.0) (2020-06-19)

### Features:

- New filter style (#10)

## [v0.2.1](https://github.com/ash-project/ash_postgres/compare/0.2.0...v0.2.1) (2020-06-15)

### Bug Fixes:

- update .formatter.exs

## [v0.2.0](https://github.com/ash-project/ash_postgres/compare/0.1.4...v0.2.0) (2020-06-14)

### Features:

- use the new DSL builder for config (#7)

## [v0.1.4](https://github.com/ash-project/ash_postgres/compare/0.1.3...v0.1.4) (2020-06-05)

### Bug Fixes:

- update ash version dependency

- account for removal of name

## [v0.1.3](https://github.com/ash-project/ash_postgres/compare/0.1.2...v0.1.3) (2020-06-03)

This release was a test of our automatic hex.pm package deployment

## Begin Changelog
