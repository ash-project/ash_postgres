defmodule AshPostgres.Test.ManualRelationshipsTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Comment, Post}

  require Ash.Query

  describe "manual first" do
    test "aggregates can be loaded with no data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      assert %{count_of_comments_containing_title: 0} =
               Ash.load!(post, :count_of_comments_containing_title)
    end

    test "aggregates can be loaded with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{count_of_comments_containing_title: 1} =
               Ash.load!(post, :count_of_comments_containing_title)
    end

    test "relationships can be filtered on with no data" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

      assert [] =
               Post |> Ash.Query.filter(comments_containing_title.title == "title") |> Ash.read!()
    end

    test "aggregates can be filtered on with no data" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

      assert [] = Post |> Ash.Query.filter(count_of_comments_containing_title == 1) |> Ash.read!()
    end

    test "aggregates can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [_] =
               Post |> Ash.Query.filter(count_of_comments_containing_title == 1) |> Ash.read!()
    end

    test "relationships can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [_] =
               Post
               |> Ash.Query.filter(comments_containing_title.title == "title2")
               |> Ash.read!()
    end
  end

  describe "manual last" do
    test "aggregates can be loaded with no data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "no match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      assert %{count_of_comments_containing_title: 0} =
               Ash.load!(comment, :count_of_comments_containing_title)
    end

    test "aggregates can be loaded with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "title2"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{count_of_comments_containing_title: 1} =
               Ash.load!(comment, :count_of_comments_containing_title)
    end

    test "aggregates can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [] =
               Comment
               |> Ash.Query.filter(count_of_comments_containing_title == 1)
               |> Ash.read!()
    end

    test "relationships can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.title == "title2")
               |> Ash.read!()
    end

    test "aggregates can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(count_of_comments_containing_title == 1)
               |> Ash.read!()
    end

    test "relationships can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.title == "title2")
               |> Ash.read!()
    end
  end

  describe "manual middle" do
    test "aggregates can be loaded with no data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "no match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      assert %{posts_for_comments_containing_title: []} =
               Ash.load!(comment, :posts_for_comments_containing_title)
    end

    test "aggregates can be loaded with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "title2"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{posts_for_comments_containing_title: ["title"]} =
               Ash.load!(comment, :posts_for_comments_containing_title)
    end

    test "aggregates can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [] =
               Comment
               |> Ash.Query.filter("title" in posts_for_comments_containing_title)
               |> Ash.read!()
    end

    test "relationships can be filtered on with no data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.post.title == "title")
               |> Ash.read!()
    end

    test "aggregates can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.post.title == "title")
               |> Ash.read!()
    end

    test "relationships can be filtered on with data" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [_, _] =
               Comment
               |> Ash.Query.filter(post.comments_containing_title.post.title == "title")
               |> Ash.read!()
    end
  end
end
