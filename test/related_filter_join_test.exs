# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.RelatedFilterJoinTest do
  @moduledoc """
  A relationship whose destination read has a filter (here `Post`'s base filter)
  is joined directly, with that filter in the join's `ON` clause, rather than
  through a subquery selecting every column of the destination.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Author, Comment, Post}

  require Ash.Query
  require Ash.Sort

  defp join_sql(query) do
    {:ok, ecto} = Ash.Query.data_layer_query(query)
    {sql, _params} = AshPostgres.TestRepo.to_sql(:all, ecto)
    sql
  end

  defp comment_on(post, title) do
    Comment
    |> Ash.Changeset.for_create(:create, %{title: title})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()
  end

  defp post(title, score) do
    Post
    |> Ash.Changeset.for_create(:create, %{title: title, score: score})
    |> Ash.create!()
  end

  test "the destination's filter is a join condition, not a subquery" do
    sql =
      Comment
      |> Ash.Query.filter(post.title == "match")
      |> join_sql()

    refute sql =~ "JOIN (SELECT", sql

    assert sql =~ ~r/JOIN "public"."posts" AS (\w+) ON \(\1."type"::varchar = \$1::varchar\) AND/,
           sql
  end

  test "a joined hop inside an exists gets the filter as a join condition" do
    sql =
      Comment
      |> Ash.Query.filter(exists(author.posts, title == "match"))
      |> join_sql()

    refute sql =~ "JOIN (SELECT", sql

    assert sql =~ ~r/JOIN "public"."posts" AS (\w+) ON \(\1."type"::varchar = \$1::varchar\) AND/,
           sql
  end

  test "a left join keeps rows whose related record is excluded by the filter" do
    actor = Ash.create!(Author, %{first_name: "actor"})
    other = Ash.create!(Author, %{first_name: "other"})

    for {title, author} <- [{"by actor", actor}, {"by other", other}] do
      Post
      |> Ash.Changeset.for_create(:create, %{title: title})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()
    end

    # `current_user_author` only matches the actor, so the other post's author
    # is filtered out of the join and its fields are null.
    assert ["by other"] =
             Post
             |> Ash.Query.filter(is_nil(current_user_author.first_name))
             |> Ash.read!(actor: actor, authorize?: false)
             |> Enum.map(& &1.title)

    assert ["by actor"] =
             Post
             |> Ash.Query.filter(current_user_author.first_name == "actor")
             |> Ash.read!(actor: actor, authorize?: false)
             |> Enum.map(& &1.title)
  end

  test "later stages can reference any column of the joined resource" do
    first = post("first", 2)
    second = post("second", 1)

    comment_on(first, "on first")
    comment_on(second, "on second")

    assert ["on second", "on first"] =
             Comment
             |> Ash.Query.filter(not is_nil(post.title))
             |> Ash.Query.sort(Ash.Sort.expr_sort(post.score, :integer))
             |> Ash.read!()
             |> Enum.map(& &1.title)
  end
end
