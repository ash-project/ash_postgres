defmodule AshPostgres.DistinctTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  setup do
    Post
    |> Ash.Changeset.new(%{title: "title"})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "title"})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "foo"})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "foo"})
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
end
