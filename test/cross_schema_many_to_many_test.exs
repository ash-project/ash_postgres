# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.CrossSchemaManyToManyTest do
  @moduledoc """
  Regression test for cross-schema many_to_many relationships.

  Test setup (two custom schemas):
  - Profile lives in "profiles" schema
  - Interest lives in "interest" schema
  - ProfileInterest (join table) lives in "profiles" schema
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Interest, Profile, ProfileInterest}

  test "load many_to_many across custom schemas" do
    profile = Ash.create!(Profile, %{description: "Test"})
    interest = Ash.create!(Interest, %{name: "eating the dogs"})

    Ash.create!(ProfileInterest, %{profile_id: profile.id, interest_id: interest.id})

    assert [%{description: "Test"}] = Ash.load!(interest, :profiles).profiles
  end
end
