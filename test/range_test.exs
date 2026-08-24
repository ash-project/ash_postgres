# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RangeTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Booking

  require Ash.Query

  @from ~U[2026-06-01 15:00:00.000000Z]
  @to ~U[2026-06-08 10:00:00.000000Z]

  defp create(attrs) do
    Booking
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create!()
  end

  defp reread(booking) do
    Booking
    |> Ash.Query.filter(id == ^booking.id)
    |> Ash.read_one!()
  end

  test "a range round trips through its native Postgres column" do
    booking =
      create(%{
        stay: %Ash.Range{lower: @from, upper: @to},
        nights: %Ash.Range{lower: ~D[2026-06-01], upper: ~D[2026-06-08]},
        guests: %Ash.Range{lower: 1, upper: 5}
      })

    assert %Booking{
             stay: %Ash.Range{lower: @from, upper: @to, bounds: :"[)"},
             nights: %Ash.Range{lower: ~D[2026-06-01], upper: ~D[2026-06-08], bounds: :"[)"},
             guests: %Ash.Range{lower: 1, upper: 5, bounds: :"[)"}
           } = reread(booking)
  end

  test "each bound's inclusivity survives storage" do
    for bounds <- [:"[)", :"[]", :"()", :"(]"] do
      booking = create(%{stay: %Ash.Range{lower: @from, upper: @to, bounds: bounds}})

      assert %Booking{stay: %Ash.Range{lower: @from, upper: @to, bounds: ^bounds}} =
               reread(booking)
    end
  end

  test "an unbounded end round trips as nil, not as a value" do
    booking = create(%{stay: %Ash.Range{lower: @from, upper: nil}})

    assert %Booking{stay: %Ash.Range{lower: @from, upper: nil}} = reread(booking)
  end

  test "a range unbounded at both ends round trips" do
    booking = create(%{stay: %Ash.Range{lower: nil, upper: nil}})

    assert %Booking{stay: %Ash.Range{lower: nil, upper: nil}} = reread(booking)
  end

  test "a nil range round trips as nil" do
    booking = create(%{stay: nil})

    assert %Booking{stay: nil} = reread(booking)
  end

  test "an empty range stores as Postgres's empty, not as every value" do
    booking = create(%{guests: %Ash.Range{lower: 5, upper: 5}})

    assert %{rows: [[stored, true]]} =
             AshPostgres.TestRepo.query!(
               "select guests::text, isempty(guests) from bookings where id = $1",
               [Ecto.UUID.dump!(booking.id)]
             )

    assert stored == "empty"
    assert %Booking{guests: %Ash.Range{empty?: true}} = reread(booking)
  end

  test "the migration generator gives each inner type its native range column" do
    assert AshPostgres.Type.Range.pg_range_type(inner_type: Ash.Type.DateTime) == :tstzrange
    assert AshPostgres.Type.Range.pg_range_type(inner_type: Ash.Type.Date) == :daterange
    assert AshPostgres.Type.Range.pg_range_type(inner_type: Ash.Type.NaiveDatetime) == :tsrange
    assert AshPostgres.Type.Range.pg_range_type(inner_type: Ash.Type.Integer) == :int8range
  end

  test "the stored column really is a native range, readable by Postgres operators" do
    booking = create(%{guests: %Ash.Range{lower: 1, upper: 5}})

    assert %{rows: [[true, false]]} =
             AshPostgres.TestRepo.query!(
               "select guests @> 3::bigint, guests @> 9::bigint from bookings where id = $1",
               [Ecto.UUID.dump!(booking.id)]
             )
  end
end
