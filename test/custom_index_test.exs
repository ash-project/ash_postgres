defmodule AshPostgres.Test.CustomIndexTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  test "unique constraint errors are properly caught" do
    Post
    |> Ash.Changeset.new(%{title: "first", uniq_custom_one: "what", uniq_custom_two: "what2"})
    |> Api.create!()

    assert_raise Ash.Error.Invalid,
                 ~r/Invalid value provided for uniq_custom_one: dude what the heck/,
                 fn ->
                   Post
                   |> Ash.Changeset.new(%{
                     title: "first",
                     uniq_custom_one: "what",
                     uniq_custom_two: "what2"
                   })
                   |> Api.create!()
                 end
  end
end
