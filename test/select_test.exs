defmodule AshPostgres.SelectTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  test "values not selected in the query are not present in the response" do
    Post
    |> Ash.Changeset.new(%{title: "title"})
    |> Api.create!()

    assert [%{title: nil}] = Api.read!(Ash.Query.select(Post, :id))
  end
end
