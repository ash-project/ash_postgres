# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.PostgrexTypesTest do
  use AshPostgres.RepoCase, async: false

  # `AshPostgres.TestRepo` configures `AshPostgres.Test.PostgrexTypes` exactly as the
  # `AshPostgres.Repo` docs tell users to, so these pin what that setup actually buys.
  test "an interval loads as a Duration, not a Postgrex.Interval" do
    assert %{rows: [[%Duration{} = duration]]} =
             Ecto.Adapters.SQL.query!(AshPostgres.TestRepo, "SELECT interval '36 hours'", [])

    assert Ash.Type.Duration.compare(duration, Duration.new!(hour: 36)) == :eq
  end

  test "months and days survive separately, as the interval stores them" do
    assert %{rows: [[%Duration{month: 14, day: 2}]]} =
             Ecto.Adapters.SQL.query!(
               AshPostgres.TestRepo,
               "SELECT interval '1 year 2 months 2 days'",
               []
             )
  end

  test "the repo's own types module is left alone" do
    assert {:ok, config} = AshPostgres.TestRepo.init(:runtime, types: SomeOtherTypes)
    assert config[:types] == SomeOtherTypes
  end

  test "nothing is supplied when a repo configures no types module" do
    assert {:ok, config} = AshPostgres.TestRepo.init(:runtime, [])
    refute Keyword.has_key?(config, :types)
  end
end
