# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.StringPositionExprTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

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
end
