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

  test "complex custom types can be used in filters" do
    Post
    |> Ash.Changeset.for_create(:create, %{point: {1.0, 2.0, 3.0}, composite_point: %{x: 1, y: 2}})
    |> Ash.create!()

    assert [_] =
             Post
             |> Ash.Query.filter(composite_point == %{x: 1, y: 2})
             |> Ash.read!()

    assert [_] =
             Post
             |> Ash.Query.filter(point == ^{1.0, 2.0, 3.0})
             |> Ash.read!()
  end

  test "complex custom types can be used in relationships" do
    [p | _] =
      for _ <- 1..4//1 do
        Post
        |> Ash.Changeset.for_create(:create, %{
          point: {1.0, 2.0, 3.0},
          string_point: "1.0,2.0,3.0"
        })
        |> Ash.create!()
      end

    p = p |> Ash.load!([:posts_with_matching_point, :posts_with_matching_string_point])

    assert Enum.count(p.posts_with_matching_point) == 3
    assert Enum.count(p.posts_with_matching_string_point) == 3

    %{id: id} =
      Post
      |> Ash.Changeset.for_create(:create)
      |> Ash.Changeset.manage_relationship(:db_point, %{id: {2.0, 3.0, 4.0}}, type: :create)
      |> Ash.create!()

    [p] =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.load(:db_point)
      |> Ash.Query.filter(id == ^id)
      |> Ash.read!()

    assert p.db_point_id == {2.0, 3.0, 4.0}
    assert p.db_point.id == {2.0, 3.0, 4.0}

    %{id: id} =
      Post
      |> Ash.Changeset.for_create(:create)
      |> Ash.Changeset.manage_relationship(:db_string_point, %{id: "2.0,3.0,4.0"}, type: :create)
      |> Ash.create!()

    [p] =
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.load(:db_string_point)
      |> Ash.Query.filter(id == ^id)
      |> Ash.read!()

    assert %{x: 2.0, y: 3.0, z: 4.0} = p.db_string_point_id
    assert %{x: 2.0, y: 3.0, z: 4.0} = p.db_string_point.id
  end

  test "casting integer to string works" do
    Post |> Ash.Changeset.for_create(:create) |> Ash.create!()

    post = Ash.Query.for_read(Post, :with_version_check, version: 1) |> Ash.read!()
    refute is_nil(post)
  end
end
