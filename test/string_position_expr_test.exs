# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.StringPositionExprTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  defp matching(title, filter) do
    post = Post |> Ash.Changeset.for_create(:create, %{title: title}) |> Ash.create!()

    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.do_filter(filter)
    |> Ash.read!()
  end

  defp position(title, substring) do
    post = Post |> Ash.Changeset.for_create(:create, %{title: title}) |> Ash.create!()

    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.calculate(:position, :integer, expr(string_position(title, ^substring)))
    |> Ash.read_one!()
    |> Map.get(:calculations)
    |> Map.get(:position)
  end

  test "a match at the start of the string is zero" do
    assert position("alpha", "a") == 0
  end

  test "a match inside the string is zero based" do
    assert position("alpha", "pha") == 2
  end

  test "a substring that is absent is nil" do
    assert position("alpha", "zzz") == nil
  end

  test "the whole string matches at zero" do
    assert position("alpha", "alpha") == 0
  end

  test "a ci_string is matched case insensitively, and still zero based" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "t", category: "Alpha"})
      |> Ash.create!()

    assert Post
           |> Ash.Query.filter(id == ^post.id)
           |> Ash.Query.calculate(:position, :integer, expr(string_position(category, "PHA")))
           |> Ash.read_one!()
           |> Map.get(:calculations)
           |> Map.get(:position) == 2
  end

  test "a double digit position is greater than a single digit one" do
    assert [_] = matching("aaaaaaaaaaz", expr(string_position(title, "z") > 9))
  end

  test "a double digit position is not less than a single digit one" do
    assert [] = matching("aaaaaaaaaaz", expr(string_position(title, "z") < 9))
  end

  test "a single digit position is less than a double digit one" do
    assert [_] = matching("aaz", expr(string_position(title, "z") < 10))
  end
end
