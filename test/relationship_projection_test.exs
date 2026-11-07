# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RelationshipProjectionTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Comment, Post}
  require Ash.Query
  require Ash.Sort
  import Ash.Expr

  test "calculations, filtering and sorting keep the same latest related row" do
    posts =
      for title <- ["first", "second", "empty"],
          do: Ash.create!(Ash.Changeset.for_create(Post, :create, %{title: title}))

    [first, second, empty] = posts

    for {post, title, likes, created_at} <- [
          {first, "old", 10, ~U[2026-01-01 00:00:00.000000Z]},
          {first, "new", 2, ~U[2026-01-02 00:00:00.000000Z]},
          {second, "other", 8, ~U[2026-01-02 00:00:00.000000Z]}
        ] do
      Comment
      |> Ash.Changeset.for_create(:create, %{
        post_id: post.id,
        title: title,
        likes: likes,
        created_at: created_at
      })
      |> Ash.create!()
    end

    ids = Enum.map(posts, & &1.id)

    query =
      Post
      |> Ash.Query.filter(id in ^ids)
      |> Ash.Query.select([:id])
      |> Ash.Query.calculate(:latest_title, :string, expr(latest_comment.title))
      |> Ash.Query.calculate(
        :latest_created_at,
        :utc_datetime_usec,
        expr(latest_comment.created_at)
      )

    original = query |> Ash.data_layer_query!() |> Map.fetch!(:query)
    {before_sql, before_params} = TestRepo.to_sql(:all, original)
    {after_sql, after_params} = TestRepo.to_sql(:all, AshSql.Query.Projection.prune(original))
    assert before_sql =~ ~s("edited_duration" AS "edited_duration")
    refute after_sql =~ ~s("edited_duration" AS "edited_duration")
    assert before_params == after_params

    rows = Map.new(Ash.read!(query), &{&1.id, &1.calculations})
    assert rows[first.id].latest_title == "new"
    assert rows[second.id].latest_created_at == ~U[2026-01-02 00:00:00.000000Z]
    assert rows[empty.id].latest_title == nil

    assert [%{id: id}] = query |> Ash.Query.filter(latest_comment.likes > 5) |> Ash.read!()
    assert id == second.id

    sorted =
      query
      |> Ash.Query.sort([{Ash.Sort.expr_sort(latest_comment.likes), :desc_nils_last}])
      |> Ash.read!()

    assert Enum.map(sorted, & &1.id) == [second.id, first.id, empty.id]
  end

  test "loading the whole relationship still includes fields unused by calculations" do
    post = Post |> Ash.Changeset.for_create(:create, %{title: "post"}) |> Ash.create!()

    comment =
      Comment
      |> Ash.Changeset.for_create(:create, %{
        post_id: post.id,
        title: "comment",
        label: "label",
        likes: 4
      })
      |> Ash.create!()

    assert %{latest_comment: %{id: id, label: "label", likes: 4}} =
             Ash.load!(post, :latest_comment)

    assert id == comment.id
  end
end
