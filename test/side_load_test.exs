defmodule AshPostgres.Test.SideLoadTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Comment, Post}

  require Ash.Query

  test "has_many relationships can be loaded" do
    assert %Post{comments: %Ash.NotLoaded{type: :relationship}} =
             post =
             Post
             |> Ash.Changeset.new(%{title: "title"})
             |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    results =
      Post
      |> Ash.Query.load(:comments)
      |> Api.read!()

    assert [%Post{comments: [%{title: "match"}]}] = results
  end

  test "belongs_to relationships can be loaded" do
    assert %Comment{post: %Ash.NotLoaded{type: :relationship}} =
             comment =
             Comment
             |> Ash.Changeset.new(%{})
             |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.replace_relationship(:comments, [comment])
    |> Api.create!()

    results =
      Comment
      |> Ash.Query.load(:post)
      |> Api.read!()

    assert [%Comment{post: %{title: "match"}}] = results
  end
end
