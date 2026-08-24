# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RoundExprTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  defp calculate(post, name, type, expression) do
    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.calculate(name, type, expression)
    |> Ash.read_one!()
    |> Map.get(:calculations)
    |> Map.get(name)
  end

  test "round with no precision rounds to no decimal places" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "a", decimal: Decimal.new("10.50")})
      |> Ash.create!()

    assert Decimal.equal?(
             calculate(post, :rounded, :decimal, expr(round(decimal))),
             Decimal.new("11")
           )
  end

  test "round with no precision rounds a negative away from zero" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "a", decimal: Decimal.new("-2.50")})
      |> Ash.create!()

    assert Decimal.equal?(
             calculate(post, :rounded, :decimal, expr(round(decimal))),
             Decimal.new("-3")
           )
  end

  test "round to a given precision" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "a", decimal: Decimal.new("3.14159")})
      |> Ash.create!()

    assert Decimal.equal?(
             calculate(post, :rounded, :decimal, expr(round(decimal, 2))),
             Decimal.new("3.14")
           )
  end

  test "round over a float" do
    post = Post |> Ash.Changeset.for_create(:create, %{title: "a", score: 3}) |> Ash.create!()

    assert calculate(post, :rounded, :float, expr(round(type(score, :float), 2))) == 3.0
  end
end
