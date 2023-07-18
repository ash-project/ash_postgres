defmodule AshPostgres.DistinctTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  setup do
    Post
    |> Ash.Changeset.new(%{title: "title", score: 1})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "title", score: 1})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "foo", score: 2})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "foo", score: 2})
    |> Api.create!()

    :ok
  end

  test "records returned are distinct on the provided field" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(:title)
      |> Api.read!()

    assert [%{title: "foo"}, %{title: "title"}] = results
  end

  test "distinct pairs well with sort" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(title: :desc)
      |> Api.read!()

    assert [%{title: "title"}, %{title: "foo"}] = results
  end

  test "distinct pairs well with sort that does not match the distinct" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(id: :desc)
      |> Ash.Query.limit(3)
      |> Api.read!()

    assert [_, _] = results
  end

  test "distinct pairs well with sort that does not match the distinct using a limit" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(id: :desc)
      |> Ash.Query.limit(3)
      |> Api.read!()

    assert [_, _] = results
  end

  test "distinct pairs well with sort that does not match the distinct using a limit #2" do
    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(id: :desc)
      |> Ash.Query.limit(1)
      |> Api.read!()

    assert [_] = results
  end

  test "distinct can use calculations sort that does not match the distinct using a limit #2" do
    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.sort(:negative_score)
      |> Ash.Query.load(:negative_score)
      |> Api.read!()

    assert [
             %{title: "foo", negative_score: -2},
             %{title: "title", negative_score: -1}
           ] = results

    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.sort(negative_score: :desc)
      |> Ash.Query.load(:negative_score)
      |> Api.read!()

    assert [
             %{title: "title", negative_score: -1},
             %{title: "foo", negative_score: -2}
           ] = results

    results =
      Post
      |> Ash.Query.distinct(:negative_score)
      |> Ash.Query.sort(:title)
      |> Ash.Query.load(:negative_score)
      |> Api.read!()

    assert [
             %{title: "foo", negative_score: -2},
             %{title: "title", negative_score: -1}
           ] = results
  end
end
