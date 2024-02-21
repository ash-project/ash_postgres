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

  test "bulk destroys only apply to things that the query produces" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(title == "fred")
    |> Api.bulk_destroy!(:update, %{})

    # 😢 sad
    assert [%{title: "george"}] = Api.read!(Post)
  end

  test "the query can join to related tables when necessary" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(author.first_name == "fred" or title == "fred")
    |> Api.bulk_destroy!(:update, %{}, return_records?: true)

    assert [%{title: "george"}] = Api.read!(Post)
  end

  test "bulk destroys can be done even on stream inputs" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Api.read!()
    |> Api.bulk_destroy!(:destroy, %{})

    assert [] = Api.read!(Post)
  end
end
