# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MapFieldTypeExprTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  setup do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "a",
        keyword_map: [display_template: "{{foo}}", size: 3]
      })
      |> Ash.create!()

    %{post: post}
  end

  test "a field declared an integer is compared as an integer", %{post: post} do
    assert [found] =
             Post
             |> Ash.Query.filter(keyword_map[:size] == 3)
             |> Ash.read!()

    assert found.id == post.id
  end

  test "a field declared an integer orders numerically" do
    Post
    |> Ash.Changeset.for_create(:create, %{
      title: "b",
      keyword_map: [display_template: "{{bar}}", size: 10]
    })
    |> Ash.create!()

    assert [%{keyword_map: [display_template: "{{bar}}", size: 10]}] =
             Post
             |> Ash.Query.filter(keyword_map[:size] > 9)
             |> Ash.read!()
  end

  test "a field declared a string still compares as a string", %{post: post} do
    assert [found] =
             Post
             |> Ash.Query.filter(keyword_map[:display_template] == "{{foo}}")
             |> Ash.read!()

    assert found.id == post.id
  end
end
