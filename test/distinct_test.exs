defmodule AshPostgres.DistinctTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  test "records returned are distinct on the provided field" do
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

    results =
      Post
      |> Ash.Query.distinct(:title)
      |> Ash.Query.sort(:title)
      |> Api.read!()

    assert [%{title: "foo"}, %{title: "title"}] = results
  end
end
