# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CompositeTypeTest do
  use AshPostgres.RepoCase
  alias AshPostgres.Test.Post
  require Ash.Query

  test "can be cast and stored" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "locked", composite_point: %{x: 1, y: 2}})
      |> Ash.create!()

    assert post.composite_point.x == 1
    assert post.composite_point.y == 2
  end

  test "can be referenced in expressions" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "locked", composite_point: %{x: 1, y: 2}})
      |> Ash.create!()

    post_id = post.id

    assert %{id: ^post_id} = Post |> Ash.Query.filter(composite_point[:x] == 1) |> Ash.read_one!()
    refute Post |> Ash.Query.filter(composite_point[:x] == 2) |> Ash.read_one!()
  end

  test "an unresolved composite path segment is rejected rather than spliced into SQL" do
    {:ok, get_path} =
      Ash.Query.Function.GetPath.new([
        Ash.Expr.ref(:composite_point),
        [:"x /*ASH_SQL_INJECTED*/"]
      ])

    assert_raise Ash.Error.Query.InvalidExpression, fn ->
      Post
      |> Ash.Query.filter(^get_path == 0)
      |> Ash.Query.data_layer_query()
    end
  end

  test "composite types can be constructed" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "locked", composite_point: %{x: 1, y: 2}})
    |> Ash.create!()

    assert %{composite_origin: %{x: 0, y: 0}} =
             Post
             |> Ash.Query.load(:composite_origin)
             |> Ash.read_one!()
  end
end
