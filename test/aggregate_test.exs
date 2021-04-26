defmodule AshPostgres.AggregateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Comment, Post}

  require Ash.Query

  describe "count" do
    test "with no related data it returns 0" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      assert %{count_of_comments: 0} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments)
               |> Api.read_one!()
    end

    test "with data, it returns the count" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{count_of_comments: 1} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments)
               |> Api.read_one!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{count_of_comments: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments)
               |> Api.read_one!()
    end

    test "with data and a filter, it returns the count" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{count_of_comments_called_match: 1} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments_called_match)
               |> Api.read_one!()

      Comment
      |> Ash.Changeset.new(%{title: "not_match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{count_of_comments_called_match: 1} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments_called_match)
               |> Api.read_one!()
    end
  end

  describe "list" do
    test "with no related data it returns an empty list" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      assert %{comment_titles: []} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles)
               |> Api.read_one!()
    end

    test "with related data, it returns the value" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "bbb"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "ccc"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{comment_titles: ["bbb", "ccc"]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles)
               |> Api.read_one!()

      Comment
      |> Ash.Changeset.new(%{title: "aaa"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{comment_titles: ["aaa", "bbb", "ccc"]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles)
               |> Api.read_one!()
    end
  end

  describe "first" do
    test "with no related data it returns nil" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      assert %{first_comment: nil} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment)
               |> Api.read_one!()
    end

    test "with related data, it returns the value" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{first_comment: "match"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment)
               |> Api.read_one!()

      Comment
      |> Ash.Changeset.new(%{title: "early match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{first_comment: "early match"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment)
               |> Api.read_one!()
    end

    test "it can be sorted on" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{first_comment: "match"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment)
               |> Ash.Query.sort(:first_comment)
               |> Api.read_one!()
    end
  end

  describe "sum" do
    test "with no related data it returns nil" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      assert %{sum_of_comment_likes: nil} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes)
               |> Api.read_one!()
    end

    test "with data, it returns the sum" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match", likes: 2})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{sum_of_comment_likes: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes)
               |> Api.read_one!()

      Comment
      |> Ash.Changeset.new(%{title: "match", likes: 3})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{sum_of_comment_likes: 5} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes)
               |> Api.read_one!()
    end

    test "with data and a filter, it returns the sum" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "match", likes: 2})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{sum_of_comment_likes_called_match: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Api.read_one!()

      Comment
      |> Ash.Changeset.new(%{title: "not_match", likes: 3})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      assert %{sum_of_comment_likes_called_match: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Api.read_one!()
    end
  end
end
