defmodule AshPostgres.Timestamptz do
  @moduledoc """
  Implements the PostgresSQL [timestamptz](https://www.postgresql.org/docs/current/datatype-datetime.html) (aka `timestamp with time zone`) type.

  Postgres [*strongly recommends*](https://wiki.postgresql.org/wiki/Don%27t_Do_This#Don.27t_use_timestamp_.28without_time_zone.29) using this type instead of the standard timestamps/datetimes without a time zone. Generally speaking, it is best practice to use the [nanosecond-precision](`AshPostgres.TimestamptzUsec`) variant.

  The basic reason `timestamptz` exists is to guarantee that the precise moment in time is stored as microseconds since January 1st, 2000 in UTC. This guarantee eliminates many time arithmetic problems, and ensures portability.

  It does not actually store a timezone, in spite of the name. As far as Elixir/Ecto is concerned, it is always of type `DateTime` and set to UTC. Using this type ensures Postgres internally uses the same contract as Ecto's `:utc_datetime`, which is to always store `DateTime` in UTC. This is especially helpful if you need to do complex time arithmetic in SQL fragments, or build reports/materialized views that use localized time formatting.

  Using this type ubiquitously in your schemas is particularly beneficial for consistency, and this is currently [under consideration](https://github.com/ash-project/ash_postgres/issues/264) as a configuration option for the default datetime storage type.

  ```elixir
  attribute :timestamp, AshPostgres.Timestamptz
  timestamps type: AshPostgres.Timestamptz
  ```

  Alternatively, you can set up a shortname:

  ```elixir
  # config.exs
  config :ash, :custom_types, timestamptz: AshPostgres.Timestamptz
  ```

  After saving, you will need to run `mix compile ash --force`.

  ```elixir
  attribute :timestamp, :timestamptz
  timestamps type: :timestamptz
  ```

      


  """
  use Ash.Type.NewType, subtype_of: :datetime, constraints: [precision: :second]

  @impl true
  def storage_type(_constraints) do
    :timestamptz
  end
end
