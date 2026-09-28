# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.FromManyAggregateSortTest do
  @moduledoc """
  A `from_many?` relationship carries a sort, and that sort decides which single
  row it resolves to. Aggregating through one has to honour it.

  Each test needs at least two related rows whose order is the answer: with one
  row every candidate implementation agrees, so the sort goes untested and an
  unordered `LIMIT 1` passes.
  """
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  alias AshPostgres.Test.Author
  alias AshPostgres.Test.Comment
  alias AshPostgres.Test.Post

  defp comment_on(post, title, created_at) do
    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: title,
      post_id: post.id,
      created_at: created_at
    })
    |> Ash.create!()
  end

  test "aggregating directly through a from_many? relationship uses its sort" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post"})
      |> Ash.create!()

    comment_on(post, "oldest", ~U[2024-01-01 00:00:00Z])
    comment_on(post, "newest", ~U[2024-06-01 00:00:00Z])

    assert %{latest_comment_title_agg: "newest"} =
             Post
             |> Ash.Query.filter(id == ^post.id)
             |> Ash.Query.load(:latest_comment_title_agg)
             |> Ash.read_one!()
  end

  test "the sort survives when the from_many? relationship is not first in the path" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "author"})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post", author_id: author.id})
      |> Ash.create!()

    comment_on(post, "oldest", ~U[2024-01-01 00:00:00Z])
    comment_on(post, "newest", ~U[2024-06-01 00:00:00Z])

    assert %{latest_comment_title_across_posts: "newest"} =
             Author
             |> Ash.Query.filter(id == ^author.id)
             |> Ash.Query.load(:latest_comment_title_across_posts)
             |> Ash.read_one!()
  end

  test "loading the relationship and aggregating through it agree" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post"})
      |> Ash.create!()

    comment_on(post, "oldest", ~U[2024-01-01 00:00:00Z])
    comment_on(post, "newest", ~U[2024-06-01 00:00:00Z])

    loaded =
      Post
      |> Ash.Query.filter(id == ^post.id)
      |> Ash.Query.load([:latest_comment, :latest_comment_title_agg])
      |> Ash.read_one!()

    assert loaded.latest_comment.title == loaded.latest_comment_title_agg
  end
end
