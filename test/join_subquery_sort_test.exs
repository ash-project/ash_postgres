defmodule AshPostgres.JoinSubquerySortTest do
  @moduledoc """
  A sort declared on the read action behind a relationship must not be carried into
  the join subquery for a `belongs_to`, where the join discards the ordering anyway.
  """
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Comment

  require Ash.Query

  defp join_sql(query) do
    {:ok, ecto} = Ash.Query.data_layer_query(query)
    {sql, _params} = AshPostgres.TestRepo.to_sql(:all, ecto)
    sql
  end

  test "belongs_to join subquery does not carry the read action's sort" do
    sql =
      Comment
      |> Ash.Query.new()
      |> Ash.Query.filter(not is_nil(sorted_post.title))
      |> join_sql()

    assert sql =~ ~r/LEFT OUTER JOIN \(SELECT/
    refute sql =~ "ORDER BY"
  end

  test "the sorted read action still sorts when read directly" do
    for title <- ["b", "a"] do
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: title})
      |> Ash.create!()
    end

    titles =
      AshPostgres.Test.Post
      |> Ash.Query.for_read(:sorted_by_title)
      |> Ash.read!()
      |> Enum.map(& &1.title)

    assert titles == ["a", "b"]
  end
end
