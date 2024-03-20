defmodule AshPostgres.DistinctTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  setup do
    Post
    |> Ash.Changeset.new(%{title: "title", score: 1})
    |> Ash.create!()

    Post
    |> Ash.Changeset.new(%{title: "title", score: 1})
    |> Ash.create!()

    Post
    |> Ash.Changeset.new(%{title: "foo", score: 2})
    |> Ash.create!()

    Post
    |> Ash.Changeset.new(%{title: "foo", score: 2})
    |> Ash.create!()

    :ok
  end

  test "records returned are distinct on the provided field" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(:title)
      |> Ash.read!()

    assert [%{title: "foo"}, %{title: "title"}] = results
  end

  test "distinct pairs well with sort" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(title: :desc)
      |> Ash.read!()

    assert [%{title: "title"}, %{title: "foo"}] = results
  end

  test "distinct pairs well with sort that does not match the distinct" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(id: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    assert [_, _] = results
  end

  test "distinct pairs well with sort that does not match the distinct using a limit" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(id: :desc)
      |> Ash.Query.limit(3)
      |> Ash.read!()

    assert [_, _] = results
  end

  test "distinct pairs well with sort that does not match the distinct using a limit #2" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(id: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read!()

    assert [_] = results
  end

  test "distinct can use calculations sort that does not match the distinct using a limit #2" do
    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.sort(:negative_score)
      |> Ash.Query.load(:negative_score)
      |> Ash.read!()

    assert [
             %{title: "foo", negative_score: -2},
             %{title: "title", negative_score: -1}
           ] = results

    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.sort(negative_score: :desc)
      |> Ash.Query.load(:negative_score)
      |> Ash.read!()

    assert [
             %{title: "title", negative_score: -1},
             %{title: "foo", negative_score: -2}
           ] = results

    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.sort(:title)
      |> Ash.Query.load(:negative_score)
      |> Ash.read!()

    assert [
             %{title: "foo", negative_score: -2},
             %{title: "title", negative_score: -1}
           ] = results
  end

  test "distinct, join filters and sort can be combined" do
    Post
    |> Ash.Changeset.new(%{title: "a", score: 2})
    |> Ash.create!()

    Post
    |> Ash.Changeset.new(%{title: "a", score: 1})
    |> Ash.create!()

    assert [] =
             Post
             |> Ash.Query.distinct(:negative_score)
             |> Ash.Query.filter(author.first_name == "a")
             |> Ash.Query.sort(:negative_score)
             |> Ash.read!()
  end

  test "distinct sort is applied" do
    Post
    |> Ash.Changeset.new(%{title: "a", score: 2})
    |> Ash.create!()

    Post
    |> Ash.Changeset.new(%{title: "a", score: 1})
    |> Ash.create!()

    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.distinct_sort(:title)
      |> Ash.Query.sort(:negative_score)
      |> Ash.Query.load(:negative_score)
      |> Ash.read!()

    assert [
             %{title: "a", negative_score: -2},
             %{title: "a", negative_score: -1}
           ] = results

    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.distinct_sort(title: :desc)
      |> Ash.Query.sort(:negative_score)
      |> Ash.Query.load(:negative_score)
      |> Ash.read!()

    assert [
             %{title: "foo", negative_score: -2},
             %{title: "title", negative_score: -1}
           ] = results
  end

  test "distinct used on it's own" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.read!()

    assert [_, _] = results
  end
end
