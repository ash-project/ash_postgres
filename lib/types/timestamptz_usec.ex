defmodule AshPostgres.TimestamptzUsec do
  @moduledoc """
  Implements the PostgresSQL [timestamptz](https://www.postgresql.org/docs/current/datatype-datetime.html) (aka `timestamp with time zone`) type with nanosecond precision.

  ```elixir
  attribute :timestamp, AshPostgres.TimestamptzUsec
  timestamps type: AshPostgres.TimestamptzUsec
  ```

  Alternatively, you can set up a shortname:

  ```elixir
  # config.exs
  config :ash, :custom_types, timestamptz_usec: AshPostgres.TimestamptzUsec
  ```

  After saving, you will need to run `mix compile ash --force`.

  ```elixir
  attribute :timestamp, :timestamptz_usec
  timestamps type: :timestamptz_usec
  ```

      

  Please see `AshPostgres.Timestamptz` for details about the usecase for this type.
  """
  use Ash.Type.NewType, subtype_of: :datetime, constraints: [precision: :microsecond]

  @impl true
  def storage_type(_constraints) do
    :"timestamptz(6)"
  end
end
