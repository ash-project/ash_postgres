# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ErrorExprTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  test "exceptions in filters are treated as regular Ash exceptions" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      Post
      |> Ash.Query.filter(
        error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10)
      )
      |> Ash.read!()
    end
  end

  test "exceptions in calculations are treated as regular Ash exceptions" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      Post
      |> Ash.Query.calculate(
        :test,
        :string,
        expr(error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10))
      )
      |> Ash.read!()
      |> Enum.map(& &1.calculations)
    end
  end

  test "exceptions in calculations are treated as regular Ash exceptions in transactions" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      AshPostgres.TestRepo.transaction!(fn ->
        Post
        |> Ash.Query.calculate(
          :test,
          :string,
          expr(error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10))
        )
        |> Ash.read!()
        |> Enum.map(& &1.calculations)
      end)
    end
  end
end
