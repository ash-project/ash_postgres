defmodule AshPostgres.SortTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Comment, Post}

  require Ash.Query

  test "multi-column sorts work" do
    Post
    |> Ash.Changeset.new(%{title: "aaa", score: 0})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "aaa", score: 1})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "bbb", score: 0})
    |> Api.create!()

    assert [
             %{title: "aaa", score: 0},
             %{title: "aaa", score: 1},
             %{title: "bbb"}
           ] =
             Api.read!(
               Post
               |> Ash.Query.load(:count_of_comments)
               |> Ash.Query.sort(title: :asc, score: :asc)
             )
  end

  test "multi-column sorts work on inclusion" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "aaa", score: 0})
      |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "aaa", score: 1})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "bbb", score: 0})
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "aaa", likes: 1})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "bbb", likes: 1})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "aaa", likes: 2})
    |> Ash.Changeset.replace_relationship(:post, post)
    |> Api.create!()

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
      |> Api.read!()

    assert [
             %{title: "aaa", comments: [%{title: "aaa"}]},
             %{title: "aaa"},
             %{title: "bbb"}
           ] = posts
  end

  test "multicolumn sort works with a select statement" do
    Post
    |> Ash.Changeset.new(%{title: "aaa", score: 0})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "aaa", score: 1})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "bbb", score: 0})
    |> Api.create!()

    assert [
             %{title: "aaa", score: 0},
             %{title: "aaa", score: 1},
             %{title: "bbb"}
           ] =
             Api.read!(
               Post
               |> Ash.Query.sort(title: :asc, score: :asc)
               |> Ash.Query.select([:title, :score])
             )
  end

  test "calculations can be sorted on w/o loading aggregates they reference" do
    Post
    |> Ash.Query.load(:count_of_comments)
    |> Ash.Query.sort(:c_times_p)
    |> Api.read!()
  end
end
