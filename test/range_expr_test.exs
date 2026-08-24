# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RangeExprTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Booking

  require Ash.Query

  @march ~U[2026-03-01 00:00:00.000000Z]
  @april ~U[2026-04-01 00:00:00.000000Z]
  @may ~U[2026-05-01 00:00:00.000000Z]
  @june ~U[2026-06-01 00:00:00.000000Z]

  defp create(attrs) do
    Booking |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  setup do
    march_quarter =
      create(%{
        stay: %Ash.Range{lower: @march, upper: @april},
        guests: %Ash.Range{lower: 1, upper: 5}
      })

    may_onwards =
      create(%{
        stay: %Ash.Range{lower: @may, upper: @june},
        guests: %Ash.Range{lower: 4, upper: 9}
      })

    %{march_quarter: march_quarter, may_onwards: may_onwards}
  end

  test "range_overlaps/2 filters on the && operator", %{march_quarter: march_quarter} do
    window = %Ash.Range{lower: @march, upper: @may}

    assert [found] =
             Booking
             |> Ash.Query.filter(range_overlaps(stay, ^window))
             |> Ash.read!()

    assert found.id == march_quarter.id
  end

  test "range_overlaps/2 sees a shared point", %{march_quarter: mq, may_onwards: mo} do
    assert [_, _] =
             Booking
             |> Ash.Query.filter(range_overlaps(guests, ^%Ash.Range{lower: 4, upper: 6}))
             |> Ash.read!()

    refute mq.id == mo.id
  end

  test "range_lower/1 and range_upper/1 read the endpoints", %{march_quarter: march_quarter} do
    assert [found] =
             Booking
             |> Ash.Query.filter(range_lower(stay) == type(^@march, :utc_datetime_usec))
             |> Ash.read!()

    assert found.id == march_quarter.id

    assert [^found] =
             Booking
             |> Ash.Query.filter(range_upper(stay) == type(^@april, :utc_datetime_usec))
             |> Ash.read!()
  end

  test "range_contains/2 holds a point", %{march_quarter: march_quarter} do
    assert [found] =
             Booking
             |> Ash.Query.filter(range_contains(guests, type(3, :integer)))
             |> Ash.read!()

    assert found.id == march_quarter.id
  end

  test "range_contains/2 holds a range", %{march_quarter: march_quarter} do
    inner = %Ash.Range{lower: 2, upper: 4}

    assert [found] =
             Booking
             |> Ash.Query.filter(range_contains(guests, ^inner))
             |> Ash.read!()

    assert found.id == march_quarter.id
  end

  test "range_adjacent/2 finds the abutting range", %{may_onwards: may_onwards} do
    abutting = %Ash.Range{lower: @june, upper: ~U[2026-07-01 00:00:00.000000Z]}

    assert [found] =
             Booking
             |> Ash.Query.filter(range_adjacent(stay, ^abutting))
             |> Ash.read!()

    assert found.id == may_onwards.id
  end

  test "range_lower/1 sorts by where a range begins" do
    assert [%{stay: %Ash.Range{lower: @march}}, %{stay: %Ash.Range{lower: @may}}] =
             Booking
             |> Ash.Query.sort(stay: :asc)
             |> Ash.read!()
  end

  test "range_upper/1 is expressible over a discrete inner type", %{march_quarter: march_quarter} do
    assert [found] =
             Booking
             |> Ash.Query.filter(range_upper(guests) == type(5, :integer))
             |> Ash.read!()

    assert found.id == march_quarter.id
  end
end
