defmodule AshPostgres.Test.PrimaryKeyTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, IntegerPost, Post}

  require Ash.Query

  test "creates resource with integer primary key" do
    assert %IntegerPost{} = IntegerPost |> Ash.Changeset.new(%{title: "title"}) |> Api.create!()
  end

  test "creates resource with uuid primary key" do
    assert %Post{} = Post |> Ash.Changeset.new(%{title: "title"}) |> Api.create!()
  end
end
