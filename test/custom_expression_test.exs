# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CustomExpressionTest do
  use AshPostgres.RepoCase, async: false

  test "unique constraint errors are properly caught" do
    Ash.create!(AshPostgres.Test.Profile, %{description: "foo"})

    assert [_] =
             AshPostgres.Test.Profile
             |> Ash.Query.for_read(:by_indirectly_matching_description, %{term: "fop"})
             |> Ash.read!()

    assert [_] =
             AshPostgres.Test.Profile
             |> Ash.Query.for_read(:by_directly_matching_description, %{term: "fop"})
             |> Ash.read!()
  end
end
