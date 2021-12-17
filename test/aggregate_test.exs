defmodule AshPostgres.AggregateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Comment, Post, Rating}

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

    test "with data for a many_to_many, it returns the count" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      post2 =
        Post
        |> Ash.Changeset.new(%{title: "title2"})
        |> Api.create!()

      post3 =
        Post
        |> Ash.Changeset.new(%{title: "title3"})
        |> Api.create!()

      post
      |> Ash.Changeset.new()
      |> Ash.Changeset.replace_relationship(:linked_posts, [post2, post3])
      |> Api.update!()

      post2
      |> Ash.Changeset.new()
      |> Ash.Changeset.replace_relationship(:linked_posts, [post3])
      |> Api.update!()

      assert [
               %{count_of_linked_posts: 2, title: "title"},
               %{count_of_linked_posts: 1, title: "title2"}
             ] =
               Post
               |> Ash.Query.load(:count_of_linked_posts)
               |> Ash.Query.filter(count_of_linked_posts >= 1)
               |> Ash.Query.sort(count_of_linked_posts: :desc)
               |> Api.read!()
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

  test "related aggregates can be filtered on" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

    post2 =
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "non_match"})
    |> Ash.Changeset.replace_relationship(:post, post2)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "non_match2"})
    |> Ash.Changeset.replace_relationship(:post, post2)
    |> Api.create!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(post.count_of_comments == 1)
             |> Api.read_one!()
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

    test "with no related data and a default it returns the default" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      assert %{sum_of_comment_likes_with_default: 0} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_with_default)
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

    test "filtering on a nested aggregate works" do
      Post
      |> Ash.Query.filter(count_of_comment_ratings == 0)
      |> Api.read!()
    end

    test "nested first aggregate works" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      comment =
        Comment
        |> Ash.Changeset.new(%{title: "title", likes: 2})
        |> Ash.Changeset.replace_relationship(:post, post)
        |> Api.create!()

      Rating
      |> Ash.Changeset.new(%{score: 10, resource_id: comment.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Api.create!()

      post =
        Post
        |> Ash.Query.load(:highest_rating)
        |> Api.read!()
        |> Enum.at(0)

      assert post.highest_rating == 10
    end

    test "loading a nested aggregate works" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title", likes: 2})
      |> Ash.Changeset.replace_relationship(:post, post)
      |> Api.create!()

      Post
      |> Ash.Query.load(:count_of_comment_ratings)
      |> Api.read!()
      |> Enum.map(fn post ->
        assert post.count_of_comment_ratings == 0
      end)
    end

    test "the sum can be filtered on when paginating" do
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

      assert %Ash.Page.Offset{results: [%{sum_of_comment_likes_called_match: 2}]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Ash.Query.filter(sum_of_comment_likes_called_match == 2)
               |> Api.read!(action: :paginated, page: [limit: 1, count: true])

      assert %Ash.Page.Offset{results: []} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Ash.Query.filter(sum_of_comment_likes_called_match == 3)
               |> Api.read!(action: :paginated, page: [limit: 1, count: true])
    end
  end
end
