defmodule AshPostgres.BulkDestroyTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Expr
  require Ash.Query

  test "bulk destroys can run with nothing in the table" do
    Api.bulk_destroy!(Post, :update, %{title: "new_title"})
  end

  test "bulk destroys destroy everything pertaining to the query" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Api.bulk_destroy!(Post, :update, %{})

    assert Api.read!(Post) == []
  end

  test "bulk updates only apply to things that the query produces" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(title == "fred")
    |> Api.bulk_destroy!(:update, %{})

    # 😢 sad
    assert [%{title: "george"}] = Api.read!(Post)
  end
end
