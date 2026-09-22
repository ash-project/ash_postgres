# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.CastErrorTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Comment, Post}

  require Ash.Query

  # Ash does not cast filter values against the attribute type, so a value that cannot be
  # cast reaches Ecto, which raises `Ecto.Query.CastError` while planning the query. The
  # data layer converts that to `InvalidFilterValue`; these cover the paths where it did not.
  defp bad_id, do: Ash.Query.filter(Post, id == "not-a-uuid")

  defp invalid_filter_value?({:error, %Ash.Error.Invalid{errors: errors}}),
    do: match?([%Ash.Error.Query.InvalidFilterValue{}], errors)

  defp invalid_filter_value?(_), do: false

  setup do
    for title <- ["one", "two"] do
      post = Post |> Ash.Changeset.for_create(:create, %{title: title}) |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "c"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()
    end

    :ok
  end

  test "count, exists and aggregate return an invalid filter value instead of raising" do
    assert invalid_filter_value?(Ash.count(bad_id()))
    assert invalid_filter_value?(Ash.exists(bad_id()))
    assert invalid_filter_value?(Ash.aggregate(bad_id(), [{:count, :count}]))
  end

  test "a count under a limit unwraps the subquery error" do
    assert invalid_filter_value?(bad_id() |> Ash.Query.limit(1) |> Ash.count())
  end

  test "a limited relationship load across several parents unwraps the subquery error" do
    comments = Comment |> Ash.Query.filter(id == "not-a-uuid") |> Ash.Query.limit(1)

    assert invalid_filter_value?(Post |> Ash.Query.load(comments: comments) |> Ash.read())
  end

  test "a relationship filter on a paginated read unwraps the subquery error" do
    query = Ash.Query.filter_input(Post, %{comments: %{id: %{eq: "not-a-uuid"}}})

    assert invalid_filter_value?(Ash.read(query, action: :paginated, page: [limit: 5]))
  end

  test "a valid id still works on every path" do
    [post | _] = Ash.read!(Post)
    query = Ash.Query.filter(Post, id == ^post.id)

    assert {:ok, 1} = Ash.count(query)
    assert {:ok, true} = Ash.exists(query)
    assert {:ok, 1} = query |> Ash.Query.limit(1) |> Ash.count()

    comments = Comment |> Ash.Query.filter(post_id == ^post.id) |> Ash.Query.limit(1)
    assert {:ok, [_, _]} = Post |> Ash.Query.load(comments: comments) |> Ash.read()
  end
end
