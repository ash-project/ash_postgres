# Using Postgres 18

Postgres 18 adds built-in functions for working with version 7 (time-ordered) UUIDs.

`AshPostgres` adds a `uuid_generate_v7` function to the database as part of the initial migration.
This Ash function is normally used as the default for `Ash.Type.UUIDv7` types.

## Using Postgres 18's Built-In `uuidv7`
To take advantage of Postgres 18's built-in `uuidv7` function, you need to update your `Repo.min_pg_version/0` to a `Version` with `major` at 18 or above.

```elixir
  def min_pg_version do
    %Version{major: 18, minor: 0, patch: 0}
  end
```

Then when you run `ash.codegen`, migrations will be added to update the defaults for your `UUIDv7` type attributes.

```sh
$ mix ash.codegen update_uuid_v7_default
```

Giving you migrations like so
```elixir
  def up do
    alter table(:items) do
      modify(:id, :uuid, default: fragment("uuidv7()"))
    end
  end

  def down do
    alter table(:items) do
      modify(:id, :uuid, default: fragment("uuid_generate_v7()"))
    end
  end
```

The Ash function `uuid_generate_v7` won't be automatically removed for you, but you can add a migration to remove this on your own.
```elixir

defmodule SomeProject.Repo.Migrations.RemoveAshUuidv7 do
  use Ecto.Migration

  def up do
    execute("DROP FUNCTION IF EXISTS uuid_generate_v7")
  end

  def down do
    # copied from initialize_extensions_1 migration
    execute("""
    CREATE OR REPLACE FUNCTION uuid_generate_v7()
    RETURNS UUID
    AS $$
    DECLARE
      timestamp    TIMESTAMPTZ;
      microseconds INT;
    BEGIN
      timestamp    = clock_timestamp();
      microseconds = (cast(extract(microseconds FROM timestamp)::INT - (floor(extract(milliseconds FROM timestamp))::INT * 1000) AS DOUBLE PRECISION) * 4.096)::INT;

      RETURN encode(
        set_byte(
          set_byte(
            overlay(uuid_send(gen_random_uuid()) placing substring(int8send(floor(extract(epoch FROM timestamp) * 1000)::BIGINT) FROM 3) FROM 1 FOR 6
          ),
          6, (b'0111' || (microseconds >> 8)::bit(4))::bit(8)::int
        ),
        7, microseconds::bit(8)::int
      ),
      'hex')::UUID;
    END
    $$
    LANGUAGE PLPGSQL
    SET search_path = ''
    VOLATILE;
    """)
  end
end
```

## Opt Out of Changing Defaults

If you want to upgrade your `min_pg_version` *without* changing the default for `UUIDv7`s, you can override the `use_builtin_uuidv7_function?` callback in your `Repo` module.

```elixir
defmodule SomeProject.Repo do
  use AshPostgres.Repo, otp_app: :some_project

  def min_pg_version do
    %Version{major: 18, minor: 0, patch: 0}
  end

  def use_builtin_uuidv7_function?, do: false

  ...
end
```
