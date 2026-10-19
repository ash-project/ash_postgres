# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.QueryAggregateReselectTest do
  use AshPostgres.RepoCase, async: false
  require Ash.Query
  alias AshPostgres.Test.{Comment, Post}

  setup do
    post = Ash.create!(Post, %{title: "post"})
    Ash.create!(Comment, %{title: "comment", post_id: post.id})

    query = Ash.Query.aggregate(Post, "count", :count, :comments)
    %{query: query, ref: %Ash.Query.Ref{attribute: query.aggregates["count"], resource: Post}}
  end

  test "filter by a query aggregate", %{query: query, ref: ref} do
    assert [%{aggregates: %{"count" => 1}}] =
             query |> Ash.Query.filter(^ref > 0) |> Ash.read!()
  end

  test "sort by a query aggregate", %{query: query} do
    assert [%{aggregates: %{"count" => 1}}] =
             query |> Ash.Query.sort([{query.aggregates["count"], :desc}]) |> Ash.read!()
  end

  test "filter by a query aggregate with a limit", %{query: query, ref: ref} do
    assert [%{aggregates: %{"count" => 1}}] =
             query |> Ash.Query.filter(^ref > 0) |> Ash.Query.limit(1) |> Ash.read!()
  end

  test "sort by a query aggregate with a limit", %{query: query} do
    assert [%{aggregates: %{"count" => 1}}] =
             query
             |> Ash.Query.sort([{query.aggregates["count"], :desc}])
             |> Ash.Query.limit(1)
             |> Ash.read!()
  end

  test "filter by a query aggregate when another aggregate wraps the query in a subquery",
       %{query: query, ref: ref} do
    assert [%{aggregates: %{"count" => 1}, comment_titles: ["comment"]}] =
             query
             |> Ash.Query.load(:comment_titles)
             |> Ash.Query.filter(^ref > 0)
             |> Ash.Query.limit(1)
             |> Ash.read!()
  end

  test "filter by a first query aggregate" do
    query = Ash.Query.aggregate(Post, "first_title", :first, :comments, field: :title)
    ref = %Ash.Query.Ref{attribute: query.aggregates["first_title"], resource: Post}

    assert [%{aggregates: %{"first_title" => "comment"}}] =
             query |> Ash.Query.filter(^ref == "comment") |> Ash.read!()
  end

  test "filter by a resource aggregate that is also loaded" do
    assert [%{count_of_comments: 1, comment_titles: ["comment"]}] =
             Post
             |> Ash.Query.filter(count_of_comments > 0)
             |> Ash.Query.load([:count_of_comments, :comment_titles])
             |> Ash.Query.limit(1)
             |> Ash.read!()
  end
end
