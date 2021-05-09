defmodule AshPostgres.Test.LoadTest do
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

  test "many_to_many loads work" do
    source_post =
      Post
      |> Ash.Changeset.new(%{title: "source"})
      |> Api.create!()

    destination_post =
      Post
      |> Ash.Changeset.new(%{title: "destination"})
      |> Api.create!()

    source_post
    |> Ash.Changeset.new()
    |> Ash.Changeset.replace_relationship(:linked_posts, [destination_post])
    |> Api.update!()

    results =
      source_post
      |> Api.load!(:linked_posts)

    assert %{linked_posts: [%{title: "destination"}]} = results
  end

  describe "lateral join loads" do
    test "lateral join loads (loads with limits or offsets) are supported" do
      assert %Post{comments: %Ash.NotLoaded{type: :relationship}} =
               post =
               Post
               |> Ash.Changeset.new(%{title: "title"})
               |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "abc"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "def"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      comments_query =
        Comment
        |> Ash.Query.limit(1)
        |> Ash.Query.sort(:title)

      results =
        Post
        |> Ash.Query.load(comments: comments_query)
        |> Api.read!()

      assert [%Post{comments: [%{title: "abc"}]}] = results

      comments_query =
        Comment
        |> Ash.Query.limit(1)
        |> Ash.Query.sort(title: :desc)

      results =
        Post
        |> Ash.Query.load(comments: comments_query)
        |> Api.read!()

      assert [%Post{comments: [%{title: "def"}]}] = results

      comments_query =
        Comment
        |> Ash.Query.limit(2)
        |> Ash.Query.sort(title: :desc)

      results =
        Post
        |> Ash.Query.load(comments: comments_query)
        |> Api.read!()

      assert [%Post{comments: [%{title: "def"}, %{title: "abc"}]}] = results
    end

    test "lateral join loads with many to many relationships are supported" do
      source_post =
        Post
        |> Ash.Changeset.new(%{title: "source"})
        |> Api.create!()

      destination_post =
        Post
        |> Ash.Changeset.new(%{title: "abc"})
        |> Api.create!()

      destination_post2 =
        Post
        |> Ash.Changeset.new(%{title: "def"})
        |> Api.create!()

      source_post
      |> Ash.Changeset.new()
      |> Ash.Changeset.replace_relationship(:linked_posts, [destination_post, destination_post2])
      |> Api.update!()

      linked_posts_query =
        Post
        |> Ash.Query.limit(1)
        |> Ash.Query.sort(title: :asc)

      results =
        source_post
        |> Api.load!(linked_posts: linked_posts_query)

      assert %{linked_posts: [%{title: "abc"}]} = results

      linked_posts_query =
        Post
        |> Ash.Query.limit(2)
        |> Ash.Query.sort(title: :asc)

      results =
        source_post
        |> Api.load!(linked_posts: linked_posts_query)

      assert %{linked_posts: [%{title: "abc"}, %{title: "def"}]} = results
    end
  end
end
