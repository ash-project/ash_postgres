# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  @impl true
  def operator_overloads do
    other_types = [
      Ash.Type.UtcDatetimeUsec,
      Ash.Type.UtcDatetime,
      Ash.Type.DateTime
    ]

    # When THIS type is on the left, cast both to this type for consistent comparison
    left_overloads =
      for other <- other_types, into: %{} do
        {[__MODULE__, other], {[__MODULE__, __MODULE__], Ash.Type.Boolean}}
      end

    # When THIS type is on the right, cast both to this type for consistent comparison
    right_overloads =
      for other <- other_types, into: %{} do
        {[other, __MODULE__], {[__MODULE__, __MODULE__], Ash.Type.Boolean}}
      end

    # Same type comparison
    same_type_overload = %{
      [__MODULE__, __MODULE__] => Ash.Type.Boolean
    }

    # Cross-type comparisons with Timestamptz - use higher precision (this type)
    cross_type_overloads = %{
      [__MODULE__, AshPostgres.Timestamptz] =>
        {[__MODULE__, __MODULE__], Ash.Type.Boolean},
      [AshPostgres.Timestamptz, __MODULE__] =>
        {[__MODULE__, __MODULE__], Ash.Type.Boolean}
    }

    comparison_overloads =
      same_type_overload
      |> Map.merge(left_overloads)
      |> Map.merge(right_overloads)
      |> Map.merge(cross_type_overloads)

    %{
      :< => comparison_overloads,
      :<= => comparison_overloads,
      :> => comparison_overloads,
      :>= => comparison_overloads
    }
  end
end
