defmodule AshPostgres.Test.ManualRelationshipsTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Comment, Post}

  require Ash.Query

  describe "manual first" do
    test "aggregates can be loaded with no data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      assert %{count_of_comments_containing_title: 0} =
               Api.load!(post, :count_of_comments_containing_title)
    end

    test "aggregates can be loaded with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert %{count_of_comments_containing_title: 1} =
               Api.load!(post, :count_of_comments_containing_title)
    end

    test "relationships can be filtered on with no data" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      assert [] =
               Post |> Ash.Query.filter(comments_containing_title.title == "title") |> Api.read!()
    end

    test "aggregates can be filtered on with no data" do
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

      assert [] = Post |> Ash.Query.filter(count_of_comments_containing_title == 1) |> Api.read!()
    end

    test "aggregates can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [_] =
               Post |> Ash.Query.filter(count_of_comments_containing_title == 1) |> Api.read!()
    end

    test "relationships can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [_] =
               Post
               |> Ash.Query.filter(comments_containing_title.title == "title2")
               |> Api.read!()
    end
  end

  describe "manual last" do
    test "aggregates can be loaded with no data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      comment =
        Comment
        |> Ash.Changeset.new(%{title: "no match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Api.create!()

      assert %{count_of_comments_containing_title: 0} =
               Api.load!(comment, :count_of_comments_containing_title)
    end

    test "aggregates can be loaded with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      comment =
        Comment
        |> Ash.Changeset.new(%{title: "title2"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert %{count_of_comments_containing_title: 1} =
               Api.load!(comment, :count_of_comments_containing_title)
    end

    test "aggregates can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [] =
               Comment
               |> Ash.Query.filter(count_of_comments_containing_title == 1)
               |> Api.read!()
    end

    test "relationships can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.title == "title2")
               |> Api.read!()
    end

    test "aggregates can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(count_of_comments_containing_title == 1)
               |> Api.read!()
    end

    test "relationships can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.title == "title2")
               |> Api.read!()
    end
  end

  describe "manual middle" do
    test "aggregates can be loaded with no data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      comment =
        Comment
        |> Ash.Changeset.new(%{title: "no match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Api.create!()

      assert %{posts_for_comments_containing_title: []} =
               Api.load!(comment, :posts_for_comments_containing_title)
    end

    test "aggregates can be loaded with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      comment =
        Comment
        |> Ash.Changeset.new(%{title: "title2"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert %{posts_for_comments_containing_title: ["title"]} =
               Api.load!(comment, :posts_for_comments_containing_title)
    end

    test "aggregates can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [] =
               Comment
               |> Ash.Query.filter("title" in posts_for_comments_containing_title)
               |> Api.read!()
    end

    test "relationships can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.post.title == "title")
               |> Api.read!()
    end

    test "aggregates can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.post.title == "title")
               |> Api.read!()
    end

    test "relationships can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "title"})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.post.title == "title")
               |> Api.read!()
    end
  end
end
