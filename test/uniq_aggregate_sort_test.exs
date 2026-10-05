# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.UniqAggregateSortTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Comment
  alias AshPostgres.Test.Post

  require Ash.Query

  setup do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post"})
      |> Ash.create!()

    for {title, likes} <- [{"b", 1}, {"a", 5}, {"b", 9}] do
      Comment
      |> Ash.Changeset.for_create(:create, %{title: title, likes: likes})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()
    end

    %{post: post}
  end

  test "uniq? aggregate sorted by the aggregated field still works" do
    assert ["a", "b"] ==
             Post
             |> Ash.read_one!()
             |> Ash.load!(:uniq_comment_titles)
             |> Map.get(:uniq_comment_titles)
  end

  # Sorted by likes desc the titles are b, a, b. Deduping keeps each title's first
  # occurrence, matching a sort followed by `Enum.uniq/1`.
  test "uniq? aggregate sorted by a different field keeps first occurrences in sort order" do
    assert ["b", "a"] ==
             Post
             |> Ash.read_one!()
             |> Ash.load!(:uniq_comment_titles_sorted_by_likes)
             |> Map.get(:uniq_comment_titles_sorted_by_likes)
  end

  test "uniq? aggregate inherits a sort declared on the relationship" do
    assert ["b", "a"] ==
             Post
             |> Ash.read_one!()
             |> Ash.load!(:uniq_titles_of_comments_sorted_by_likes)
             |> Map.get(:uniq_titles_of_comments_sorted_by_likes)
  end

  test "uniq? aggregate sorted by a different field respects the aggregate's filter" do
    assert ["a"] ==
             Post
             |> Ash.read_one!()
             |> Ash.load!(:uniq_popular_comment_titles_sorted_by_likes)
             |> Map.get(:uniq_popular_comment_titles_sorted_by_likes)
  end

  test "uniq? aggregate sorted by a different field can be filtered on" do
    assert [_] =
             Post
             |> Ash.Query.filter(uniq_comment_titles_sorted_by_likes == ["b", "a"])
             |> Ash.read!()

    assert [] =
             Post
             |> Ash.Query.filter(uniq_comment_titles_sorted_by_likes == ["a", "b"])
             |> Ash.read!()
  end
end
