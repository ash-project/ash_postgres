defmodule AshPostgres.SelectTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "values not selected in the query are not present in the response" do
    Post
    |> Ash.Changeset.new(%{title: "title"})
    |> Ash.create!()

    assert [%{title: nil}] = Ash.read!(Ash.Query.select(Post, :id))
  end
end
