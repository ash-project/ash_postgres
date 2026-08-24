# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ArrayLengthExprTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  defp length_of(list) do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "a", list_containing_nils: list})
      |> Ash.create!()

    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.calculate(:len, :integer, expr(length(list_containing_nils)))
    |> Ash.read_one!()
    |> Map.get(:calculations)
    |> Map.get(:len)
  end

  test "an empty list has length zero" do
    assert length_of([]) == 0
  end

  test "a populated list has its length" do
    assert length_of(["a", "b", "c"]) == 3
  end

  test "a nil list has no length" do
    assert length_of(nil) == nil
  end

  test "filtering on the length of an empty list matches" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "a", list_containing_nils: []})
      |> Ash.create!()

    assert [found] =
             Post
             |> Ash.Query.filter(length(list_containing_nils) == 0)
             |> Ash.read!()

    assert found.id == post.id
  end
end
