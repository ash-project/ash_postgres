# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.DurationOperatorTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  defp post!(title, created_at) do
    Post
    |> Ash.Changeset.for_create(:create, %{title: title, created_at: created_at})
    |> Ash.create!()
  end

  describe "adding a duration to a datetime attribute" do
    test "filters on a duration" do
      now = DateTime.utc_now()
      post!("old", DateTime.add(now, -60, :day))
      post!("recent", DateTime.add(now, -10, :day))

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(created_at + ^Duration.new!(day: 30) > ^now)
               |> Ash.read!()
    end

    test "filters on a multi-unit duration" do
      now = DateTime.utc_now()
      post!("old", DateTime.add(now, -60, :day))
      post!("recent", DateTime.add(now, -20, :day))

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(created_at + ^Duration.new!(month: 1, day: 2) > ^now)
               |> Ash.read!()
    end

    test "the duration may be on the left" do
      now = DateTime.utc_now()
      post!("old", DateTime.add(now, -60, :day))
      post!("recent", DateTime.add(now, -10, :day))

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(^Duration.new!(day: 30) + created_at > ^now)
               |> Ash.read!()
    end
  end

  describe "subtracting a duration from a datetime attribute" do
    test "filters on a duration" do
      now = DateTime.utc_now()
      post!("soon", DateTime.add(now, 10, :day))
      post!("later", DateTime.add(now, 60, :day))

      assert [%Post{title: "soon"}] =
               Post
               |> Ash.Query.filter(created_at - ^Duration.new!(day: 30) < ^now)
               |> Ash.read!()
    end

    test "filters on a multi-unit duration" do
      now = DateTime.utc_now()
      post!("soon", DateTime.add(now, 20, :day))
      post!("later", DateTime.add(now, 60, :day))

      assert [%Post{title: "soon"}] =
               Post
               |> Ash.Query.filter(created_at - ^Duration.new!(month: 1, day: 2) < ^now)
               |> Ash.read!()
    end
  end

  describe "a duration expression compared to another datetime" do
    test "both sides may be expressions" do
      now = DateTime.utc_now()
      post!("old", DateTime.add(now, -60, :day))
      post!("recent", DateTime.add(now, -10, :day))

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(
                 created_at + ^Duration.new!(day: 30) > ^now + ^Duration.new!(day: 1)
               )
               |> Ash.read!()
    end
  end
end
