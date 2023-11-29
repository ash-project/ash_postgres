defmodule AshPostgres.Test.CompositeTypeTest do
  use AshPostgres.RepoCase
  alias AshPostgres.Test.{Api, Post}
  require Ash.Query

  test "can be cast and stored" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "locked", composite_point: %{x: 1, y: 2}})
      |> Api.create!()

    assert post.composite_point.x == 1
    assert post.composite_point.y == 2
  end

  test "can be referenced in expressions" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "locked", composite_point: %{x: 1, y: 2}})
      |> Api.create!()

    post_id = post.id

    assert %{id: ^post_id} = Post |> Ash.Query.filter(composite_point[:x] == 1) |> Api.read_one!()
    refute Post |> Ash.Query.filter(composite_point[:x] == 2) |> Api.read_one!()
  end

  test "composite types can be constructed" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "locked", composite_point: %{x: 1, y: 2}})
    |> Api.create!()

    assert %{composite_origin: %{x: 0, y: 0}} =
             Post
             |> Ash.Query.load(:composite_origin)
             |> Api.read_one!()
  end
end
