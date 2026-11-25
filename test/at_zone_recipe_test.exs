# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.AtZoneRecipeTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  import Ash.Expr

  require Ash.Query

  # 02:00:00.123456 UTC on 16 June is 22:00:00.123456 on 15 June in New York (UTC-4 in June).
  @instant ~U[2026-06-16 02:00:00.123456Z]

  setup do
    # A session that is not UTC, so a conversion that leans on the session zone fails.
    AshPostgres.TestRepo.query!("SET LOCAL TIME ZONE 'America/Los_Angeles'")
    Ash.Seed.seed!(Post, %{title: "America/New_York", score: 2, created_at: @instant})
    :ok
  end

  test "converts a stored UTC timestamp" do
    assert [%Post{}] =
             Post
             |> Ash.Query.filter(
               fragment(
                 "? = timestamp '2026-06-15 22:00:00.123456'",
                 at_zone(created_at, title)
               )
             )
             |> Ash.read!()
  end

  test "converts a bound instant" do
    assert [%Post{}] =
             Post
             |> Ash.Query.filter(
               fragment(
                 "? = timestamp '2026-06-15 22:00:00.123456'",
                 at_zone(^@instant, title)
               )
             )
             |> Ash.read!()
  end

  test "converts now() anchored to as_of, and its date" do
    assert [%Post{}] =
             Post
             |> Ash.Query.as_of(@instant)
             |> Ash.Query.filter(
               fragment(
                 "? = timestamp '2026-06-15 22:00:00.123456'",
                 at_zone(now(), title)
               ) and type(at_zone(now(), title), :date) == ^~D[2026-06-15]
             )
             |> Ash.read!()
  end

  test "ago and from_now with an amount from the row are anchored to as_of" do
    assert [%Post{calculations: %{ago: ago, from_now: from_now}}] =
             Post
             |> Ash.Query.as_of(@instant)
             |> Ash.Query.calculate(:ago, :utc_datetime_usec, expr(ago(score, :day)))
             |> Ash.Query.calculate(:from_now, :utc_datetime_usec, expr(from_now(score, :day)))
             |> Ash.read!()

    assert ago == ~U[2026-06-14 02:00:00.123456Z]
    assert from_now == ~U[2026-06-18 02:00:00.123456Z]
  end
end
