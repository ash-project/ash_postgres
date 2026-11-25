# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.LocalTimeTest do
  use AshPostgres.RepoCase, async: true

  import Ash.Expr

  alias AshPostgres.Test.Post

  # The released Ash dependency may predate the local time expressions.
  if !Code.ensure_loaded?(Ash.Query.Function.LocalNow) do
    @moduletag skip: "requires Ash with local time expressions"
  end

  require Ash.Query

  test "local time expressions preserve fractional seconds and nil in SQL" do
    Ash.create!(Post, %{title: "Asia/Hong_Kong"})

    assert [%Post{}] =
             Post
             |> Ash.Query.as_of(~U[2026-11-01 20:30:00.123456Z])
             |> Ash.Query.filter(
               fragment("? = timestamp '2026-11-02 04:30:00.123456'", local_now(title)) and
                 local_today(title) == ^~D[2026-11-02] and
                 is_nil(local_today(nil))
             )
             |> Ash.read!()
  end

  test "relative intervals come before the SQL time zone conversion across daylight saving" do
    Ash.create!(Post, %{title: "America/New_York"})

    TestRepo.query!("SET LOCAL TIME ZONE 'America/Los_Angeles'")

    assert %{
             calculations: %{
               future: ~N[2026-11-02 00:30:00],
               future_duration: ~N[2026-11-02 00:30:00],
               past: ~N[2026-10-31 01:30:00],
               past_duration: ~N[2026-10-31 01:30:00]
             }
           } =
             Post
             |> Ash.Query.as_of(~U[2026-11-01 05:30:00Z])
             |> Ash.Query.calculate(
               :future,
               :naive_datetime,
               expr(local_from_now(1, :day, title))
             )
             |> Ash.Query.calculate(
               :future_duration,
               :naive_datetime,
               expr(local_from_now(^Duration.new!(day: 1), title))
             )
             |> Ash.Query.calculate(
               :past,
               :naive_datetime,
               expr(local_ago(1, :day, title))
             )
             |> Ash.Query.calculate(
               :past_duration,
               :naive_datetime,
               expr(local_ago(^Duration.new!(day: 1), title))
             )
             |> Ash.read_one!()
  end
end
