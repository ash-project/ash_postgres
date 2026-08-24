# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.DurationExprTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  defp post!(title, created_at) do
    Post
    |> Ash.Changeset.for_create(:create, %{title: title, created_at: created_at})
    |> Ash.create!()
  end

  describe "ago/1" do
    test "filters on a duration" do
      post!("old", DateTime.add(DateTime.utc_now(), -60, :day))
      post!("recent", DateTime.utc_now())

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(created_at > ago(^Duration.new!(day: 30)))
               |> Ash.read!()
    end

    test "filters on a multi-unit duration" do
      post!("old", DateTime.add(DateTime.utc_now(), -60, :day))
      post!("recent", DateTime.add(DateTime.utc_now(), -20, :day))

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(created_at > ago(^Duration.new!(month: 1, day: 2)))
               |> Ash.read!()
    end
  end

  describe "from_now/1" do
    test "filters on a duration" do
      post!("soon", DateTime.add(DateTime.utc_now(), 10, :day))
      post!("later", DateTime.add(DateTime.utc_now(), 60, :day))

      assert [%Post{title: "soon"}] =
               Post
               |> Ash.Query.filter(created_at < from_now(^Duration.new!(day: 30)))
               |> Ash.read!()
    end
  end

  describe "datetime_add/2" do
    test "adds a duration to a datetime" do
      now = DateTime.utc_now()
      post!("before", DateTime.add(now, 3, :day))
      post!("after", DateTime.add(now, 30, :day))

      assert [%Post{title: "before"}] =
               Post
               |> Ash.Query.filter(created_at < datetime_add(^now, ^Duration.new!(day: 7)))
               |> Ash.read!()
    end

    test "a negative duration subtracts" do
      now = DateTime.utc_now()
      post!("old", DateTime.add(now, -30, :day))
      post!("recent", now)

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(created_at > datetime_add(^now, ^Duration.new!(day: -7)))
               |> Ash.read!()
    end
  end

  describe "date_add/2" do
    test "adds a duration to a date, and stays a date" do
      today = Date.utc_today()
      post!("old", DateTime.add(DateTime.utc_now(), -60, :day))
      post!("recent", DateTime.utc_now())

      assert [%Post{title: "recent"}] =
               Post
               |> Ash.Query.filter(
                 type(created_at, :date) >= date_add(^today, ^Duration.new!(day: -30))
               )
               |> Ash.read!()
    end
  end
end
