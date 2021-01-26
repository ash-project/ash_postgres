defmodule AshPostgres.Test.UniqueIdentityTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  test "unique constraint errors are properly caught" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

    assert_raise Ash.Error.Invalid,
                 ~r/Invalid value provided for id: has already been taken/,
                 fn ->
                   Post
                   |> Ash.Changeset.new(%{id: post.id})
                   |> Api.create!()
                 end
  end
end
