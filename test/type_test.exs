defmodule AshPostgres.Test.TypeTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "complex custom types can be used" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", point: {1.0, 2.0, 3.0}})
      |> Ash.create!()

    assert post.point == {1.0, 2.0, 3.0}
  end

  test "complex custom types can be accessed with fragments" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title", point: {1.0, 2.0, 3.0}})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title", point: {2.0, 1.0, 3.0}})
    |> Ash.create!()

    assert [%{point: {2.0, 1.0, 3.0}}] =
             Post
             |> Ash.Query.filter(fragment("(?)[1] > (?)[2]", point, point))
             |> Ash.read!()
  end

  test "uuids can be used as strings in fragments" do
    uuid = Ash.UUID.generate()

    Post
    |> Ash.Query.filter(fragment("? = ?", id, type(^uuid, :uuid)))
    |> Ash.read!()
  end
end
