# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Type.Range do
  @moduledoc false
  # Postgres-side wrapper for the core `Ash.Type.Range` (whose logical storage is
  # `:range`). It supplies the concrete Postgres range type (tstzrange/daterange/
  # etc.) for query casts and migrations, while delegating value casting to core.
  # `ash_postgres` substitutes this for `Ash.Type.Range` in
  # `AshPostgres.SqlImplementation.parameterized_type/2` and `migration_type/2`.
  use Ash.Type

  @impl true
  def constraints, do: Ash.Type.Range.constraints()

  @impl true
  def init(constraints), do: Ash.Type.Range.init(constraints)

  @impl true
  def storage_type(constraints), do: pg_range_type(constraints)

  @impl true
  def cast_input(value, constraints), do: Ash.Type.Range.cast_input(value, constraints)

  @impl true
  def apply_constraints(value, constraints),
    do: Ash.Type.Range.apply_constraints(value, constraints)

  # Core's native representation is the `%Ash.Range{}` struct (with bounds dumped to
  # the inner type's native form). On the way to/from Postgres we reshape that into
  # the driver's `%Postgrex.Range{}`.
  @impl true
  def dump_to_native(value, constraints) do
    case Ash.Type.Range.dump_to_native(value, constraints) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, %Ash.Range{lower: lower, upper: upper, bounds: bounds}} ->
        {lower_inclusive, upper_inclusive} = inclusive(bounds)

        {:ok,
         %Postgrex.Range{
           lower: lower || :unbound,
           upper: upper || :unbound,
           lower_inclusive: lower_inclusive,
           upper_inclusive: upper_inclusive
         }}

      other ->
        other
    end
  end

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(%Postgrex.Range{} = pg, constraints) do
    range = %Ash.Range{
      lower: unbound_to_nil(pg.lower),
      upper: unbound_to_nil(pg.upper),
      bounds: bounds_from_inclusive(pg.lower_inclusive, pg.upper_inclusive)
    }

    Ash.Type.Range.cast_stored(range, constraints)
  end

  def cast_stored(value, constraints), do: Ash.Type.Range.cast_stored(value, constraints)

  @doc "The concrete Postgres range type for an `Ash.Type.Range`'s constraints."
  def pg_range_type(constraints) do
    case Ash.Type.get_type(constraints[:inner_type]) do
      Ash.Type.Date -> :daterange
      Ash.Type.NaiveDatetime -> :tsrange
      Ash.Type.Integer -> :int8range
      Ash.Type.DateTime -> :tstzrange
    end
  end

  defp inclusive(:"[)"), do: {true, false}
  defp inclusive(:"[]"), do: {true, true}
  defp inclusive(:"()"), do: {false, false}
  defp inclusive(:"(]"), do: {false, true}

  defp bounds_from_inclusive(true, false), do: :"[)"
  defp bounds_from_inclusive(true, true), do: :"[]"
  defp bounds_from_inclusive(false, false), do: :"()"
  defp bounds_from_inclusive(false, true), do: :"(]"
  defp bounds_from_inclusive(_, _), do: :"[)"

  defp unbound_to_nil(bound) when bound in [:unbound, :empty], do: nil
  defp unbound_to_nil(bound), do: bound
end
