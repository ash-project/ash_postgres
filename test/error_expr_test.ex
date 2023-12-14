defmodule AshPostgres.ErrorExprTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Author, Comment, Post}

  require Ash.Query
  import Ash.Expr

  test "exceptions in filters are treated as regular Ash exceptions" do
    Post
    |> Ash.Changeset.new(%{title: "title"})
    |> Api.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      Post
      |> Ash.Query.filter(
        error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10)
      )
      |> Api.read!()
    end
  end

  test "exceptions in calculations are treated as regular Ash exceptions" do
    Post
    |> Ash.Changeset.new(%{title: "title"})
    |> Api.create!()

    assert_raise Ash.Error.Invalid, ~r/this is bad!/, fn ->
      Post
      |> Ash.Query.calculate(
        :test,
        expr(error(Ash.Error.Query.InvalidFilterValue, message: "this is bad!", value: 10)),
        :string
      )
      |> Api.read!()
      |> Enum.map(& &1.calculations)
    end
  end
end
