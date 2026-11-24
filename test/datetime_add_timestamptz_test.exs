# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.DatetimeAddTimestamptzTest do
  @moduledoc """
  `datetime_add/3`, `datetime_add/2`, `ago/2` and `from_now/2` on timestamptz values are
  computed in UTC, whatever the session's `TimeZone`, and with only immutable SQL, so a
  bound parameter folds to a constant at plan time (which partitioned tables and
  TimescaleDB hypertables need to exclude partitions while planning).

  Ecto's `datetime_add/3` casts to `timestamp`, which depends on the session time zone
  (and so is only stable, not immutable).
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post
  alias AshPostgres.TestRepo

  require Ash.Query

  # 05:30 UTC on 2026-11-01 is 01:30 in New York, half an hour before clocks go back.
  # A day later in UTC is 05:30Z; a day later on New York's clock is 06:30Z.
  @before_dst_ends ~U[2026-11-01 05:30:00.000000Z]
  @a_utc_day_later ~U[2026-11-02 05:30:00.000000Z]

  defp post!(datetime) do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "post", datetime: datetime})
    |> Ash.create!()
  end

  # Runs `fun` with the session in New York time, so session-dependent SQL shows up.
  defp in_new_york(fun) do
    {:ok, result} =
      TestRepo.transaction(fn ->
        TestRepo.query!("SET LOCAL TIME ZONE 'America/New_York'")
        fun.()
      end)

    result
  end

  defp sql(query) do
    {:ok, ecto_query} = Ash.Query.data_layer_query(query)
    {sql, _params} = Ecto.Adapters.SQL.to_sql(:all, TestRepo, ecto_query)
    sql
  end

  describe "datetime_add/3 on a timestamptz column" do
    test "adds days in UTC, whatever the session time zone" do
      post!(@before_dst_ends)

      assert [_] =
               in_new_york(fn ->
                 Post
                 |> Ash.Query.filter(datetime_add(datetime, 1, :day) == ^@a_utc_day_later)
                 |> Ash.read!()
               end)
    end

    test "adds months in UTC, clamping to the end of the month" do
      post!(~U[2026-01-31 12:00:00.000000Z])

      assert [_] =
               Post
               |> Ash.Query.filter(
                 datetime_add(datetime, 1, :month) == ^~U[2026-02-28 12:00:00.000000Z]
               )
               |> Ash.read!()
    end

    test "uses no session-dependent casts" do
      sql =
        Post
        |> Ash.Query.filter(datetime_add(datetime, 2, :hour) > ^@before_dst_ends)
        |> sql()

      refute sql =~ "::timestamp "
      refute sql =~ "::timestamp)"
      assert sql =~ "timezone('UTC'"
    end
  end

  describe "datetime_add/2 on a timestamptz column" do
    test "adds a duration in UTC, whatever the session time zone" do
      post!(@before_dst_ends)

      assert [_] =
               in_new_york(fn ->
                 Post
                 |> Ash.Query.filter(
                   datetime_add(datetime, ^Duration.new!(day: 1)) == ^@a_utc_day_later
                 )
                 |> Ash.read!()
               end)
    end
  end

  describe "immutability" do
    test "a bound computed from parameters is folded to a constant while planning" do
      # Postgres only folds immutable expressions at plan time; a session-dependent cast
      # anywhere in the bound would leave the arithmetic in the plan.
      query =
        Post
        |> Ash.Query.filter(
          datetime >= datetime_add(datetime_add(^@before_dst_ends, -2, :day), 1, :hour)
        )

      {:ok, ecto_query} = Ash.Query.data_layer_query(query)
      plan = Ecto.Adapters.SQL.explain(TestRepo, :all, ecto_query)

      refute plan =~ "timezone("
      refute plan =~ "interval"
      assert plan =~ "2026-10-30 06:30:00"
    end
  end

  describe "compared with a timestamptz column" do
    test "a computed bound uses no session-dependent casts" do
      # The bound has no column references, so it can be evaluated before reaching SQL,
      # or computed in SQL from immutable parts only: either way, no `::timestamp`.
      sql =
        Post
        |> Ash.Query.filter(datetime >= datetime_add(now(), -2, :day))
        |> sql()

      refute sql =~ "::timestamp "
      refute sql =~ "::timestamp)"
    end

    test "ago/2 and from_now/2 compute in UTC" do
      now = DateTime.utc_now()
      post!(DateTime.add(now, -36, :hour))
      post!(DateTime.add(now, 36, :hour))

      assert [_] =
               in_new_york(fn ->
                 Post
                 |> Ash.Query.filter(datetime > ago(2, :day) and datetime < from_now(1, :day))
                 |> Ash.read!()
               end)

      sql =
        Post
        |> Ash.Query.filter(datetime > ago(2, :day) and datetime < from_now(1, :day))
        |> sql()

      refute sql =~ "::timestamp "
      refute sql =~ "::timestamp)"
    end
  end

  describe "naive timestamp columns" do
    test "keep working as before" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post", created_at: @before_dst_ends})
      |> Ash.create!()

      assert [_] =
               Post
               |> Ash.Query.filter(datetime_add(created_at, 1, :day) == ^@a_utc_day_later)
               |> Ash.read!()
    end
  end
end
