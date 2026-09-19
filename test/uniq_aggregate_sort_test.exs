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
             Post |> Ash.read_one!() |> Ash.load!(:uniq_comment_titles) |> Map.get(:uniq_comment_titles)
  end

  test "uniq? aggregate sorted by a different field discards the sort instead of erroring" do
    assert ["a", "b"] ==
             Post
             |> Ash.read_one!()
             |> Ash.load!(:uniq_comment_titles_sorted_by_likes)
             |> Map.get(:uniq_comment_titles_sorted_by_likes)
             |> Enum.sort()
  end

  test "uniq? aggregate does not inherit a sort declared on the relationship" do
    assert ["a", "b"] ==
             Post
             |> Ash.read_one!()
             |> Ash.load!(:uniq_titles_of_comments_sorted_by_likes)
             |> Map.get(:uniq_titles_of_comments_sorted_by_likes)
             |> Enum.sort()
  end
end
