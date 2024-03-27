defmodule AshPostgres.SortTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Comment, Post, PostLink}

  require Ash.Query
  require Ash.Sort

  test "multi-column sorts work" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 0})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 1})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "bbb", score: 0})
    |> Ash.create!()

    assert [
             %{title: "aaa", score: 0},
             %{title: "aaa", score: 1},
             %{title: "bbb"}
           ] =
             Ash.read!(
               Post
               |> Ash.Query.load(:count_of_comments)
               |> Ash.Query.sort(title: :asc, score: :asc)
             )
  end

  test "multi-column sorts work on inclusion" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 0})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 1})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "bbb", score: 0})
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "aaa", likes: 1})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "bbb", likes: 1})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "aaa", likes: 2})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    posts =
      Post
      |> Ash.Query.load([
        :count_of_comments,
        comments:
          Comment
          |> Ash.Query.sort([:title, :likes])
          |> Ash.Query.select([:title, :likes])
          |> Ash.Query.limit(1)
      ])
      |> Ash.Query.sort([:title, :score])
      |> Ash.read!()

    assert [
             %{title: "aaa", comments: [%{title: "aaa"}]},
             %{title: "aaa"},
             %{title: "bbb"}
           ] = posts
  end

  test "multicolumn sort works with a select statement" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 0})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 1})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "bbb", score: 0})
    |> Ash.create!()

    assert [
             %{title: "aaa", score: 0},
             %{title: "aaa", score: 1},
             %{title: "bbb"}
           ] =
             Ash.read!(
               Post
               |> Ash.Query.sort(title: :asc, score: :asc)
               |> Ash.Query.select([:title, :score])
             )
  end

  test "sorting when joining to a many to many relationship sorts properly" do
    post1 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 0})
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bbb", score: 1})
      |> Ash.create!()

    post3 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "ccc", score: 0})
      |> Ash.create!()

    PostLink
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:source_post, post1, type: :append)
    |> Ash.Changeset.manage_relationship(:destination_post, post3, type: :append)
    |> Ash.create!()

    PostLink
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:source_post, post2, type: :append)
    |> Ash.Changeset.manage_relationship(:destination_post, post2, type: :append)
    |> Ash.create!()

    PostLink
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:source_post, post3, type: :append)
    |> Ash.Changeset.manage_relationship(:destination_post, post1, type: :append)
    |> Ash.create!()

    assert [
             %{title: "aaa"},
             %{title: "bbb"},
             %{title: "ccc"}
           ] =
             Ash.read!(
               Post
               |> Ash.Query.sort(title: :asc)
               |> Ash.Query.filter(linked_posts.title in ["aaa", "bbb", "ccc"])
             )

    assert [
             %{title: "ccc"},
             %{title: "bbb"},
             %{title: "aaa"}
           ] =
             Ash.read!(
               Post
               |> Ash.Query.sort(title: :desc)
               |> Ash.Query.filter(linked_posts.title in ["aaa", "bbb", "ccc"] or title == "aaa")
             )

    assert [
             %{title: "ccc"},
             %{title: "bbb"},
             %{title: "aaa"}
           ] =
             Ash.read!(
               Post
               |> Ash.Query.sort(title: :desc)
               |> Ash.Query.filter(
                 linked_posts.title in ["aaa", "bbb", "ccc"] or
                   post_links.source_post_id == ^post2.id
               )
             )
  end

  test "calculations can be sorted on w/o loading aggregates they reference" do
    Post
    |> Ash.Query.load(:count_of_comments)
    |> Ash.Query.sort(:c_times_p)
    |> Ash.read!()
  end

  test "calculations can sort on expressions" do
    post1 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 0})
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bbb", score: 1})
      |> Ash.create!()

    post3 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "ccc", score: 0})
      |> Ash.create!()

    PostLink
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:source_post, post1, type: :append)
    |> Ash.Changeset.manage_relationship(:destination_post, post3, type: :append)
    |> Ash.create!()

    PostLink
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:source_post, post2, type: :append)
    |> Ash.Changeset.manage_relationship(:destination_post, post2, type: :append)
    |> Ash.create!()

    PostLink
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:source_post, post3, type: :append)
    |> Ash.Changeset.manage_relationship(:destination_post, post1, type: :append)
    |> Ash.create!()

    posts_query =
      Ash.Query.sort(Post, Ash.Sort.expr_sort(source(post_links.state)))

    Post
    |> Ash.Query.load(linked_posts: posts_query)
    |> Ash.read!()
  end
end
