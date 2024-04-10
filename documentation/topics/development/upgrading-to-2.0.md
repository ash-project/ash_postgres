# Upgrading to 2.0

There are only three breaking changes in this release, one of them is very significant, the other two are minor.

# AshPostgres officially supports only postgresql version 14 or higher

A new callback `min_pg_version/0` has been added to the repo, but a default implementation is set up that reads the version from postgres directly, the first time it is required. It is cached until the repo is reinitialized, at which point it is looked up again.

While _most_ things will work with versions as low as 9, we are relying on features of newer postgres versions and intend to do so more in the future. We will not be testing against versions lower than 14, and we will not be supporting them. If you are using an older version of postgres, you will need to upgrade.

If you _must_ use an older version, the only thing that you'll need to change in the short term is to handle the fact that we now use `gen_random_uuid()` as the default for generated uuids (see below), which is only available after postgres _13_. Additionally, if you are on postgres 12 or earlier, you will need to replace `ANYCOMPATIBLE` with `ANYELEMENT` in the `ash-functions` extension migration.

## `gen_random_uuid()` is now the default for generated uuids

In the past, we used `uuid_generate_v4()` as the default for generated uuids. This function is part of the `uuid-ossp` extension, which is not installed by default in postgres. `gen_random_uuid()` is a built-in function that is available in all versions of postgres 13 and higher. If you are using an older version of postgres, you will need to install the `uuid-ossp` extension and change the default in your migrations.

## utc datetimes that default to `&DateTime.now/0` are now cast to `UTC`

This is a layer of safety to ensure consistency in the default values of a database and the datetimes that are sent to/from the database. When you generate migrations you will notice your timestamps change from defaulting to `now()` in your migrations to `now() AT TIMESTAMP 'utc'`. You are free to undo this change, by setting `migration_defaults` in your resource, or simply by deleting the generated migration.
