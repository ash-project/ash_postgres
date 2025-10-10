# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.SelectTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "values not selected in the query are not present in the response" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert [%{title: %Ash.NotLoaded{}}] = Ash.read!(Ash.Query.select(Post, :id))
  end

  test "values not selected in a changeset are not present in the response" do
    assert %{title: %Ash.NotLoaded{}} =
             Post
             |> Ash.Changeset.for_create(:create, %{title: "title"})
             |> Ash.Changeset.select([])
             |> Ash.create!()
  end
end
