# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.PrimaryKeyTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{IntegerPost, Post, PostView}

  require Ash.Query

  test "creates record with integer primary key" do
    assert %IntegerPost{} =
             IntegerPost |> Ash.Changeset.for_create(:create, %{title: "title"}) |> Ash.create!()
  end

  test "creates record with uuid primary key" do
    assert %Post{} = Post |> Ash.Changeset.for_create(:create, %{title: "title"}) |> Ash.create!()
  end

  describe "resources without a primary key" do
    test "records can be created" do
      post =
        Post
        |> Ash.Changeset.for_action(:create, %{title: "not very interesting"})
        |> Ash.create!()

      assert {:ok, view} =
               PostView
               |> Ash.Changeset.for_action(:create, %{browser: :firefox, post_id: post.id})
               |> Ash.create()

      assert view.browser == :firefox
      assert view.post_id == post.id
      assert DateTime.diff(DateTime.utc_now(), view.time, :microsecond) < 1_000_000
    end

    test "records can be queried" do
      post =
        Post
        |> Ash.Changeset.for_action(:create, %{title: "not very interesting"})
        |> Ash.create!()

      expected =
        PostView
        |> Ash.Changeset.for_action(:create, %{browser: :firefox, post_id: post.id})
        |> Ash.create!()

      assert {:ok, [actual]} = Ash.read(PostView)

      assert actual.time == expected.time
      assert actual.browser == expected.browser
      assert actual.post_id == expected.post_id
    end
  end
end
