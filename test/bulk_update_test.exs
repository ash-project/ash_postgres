defmodule AshPostgres.BulkUpdateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Expr
  require Ash.Query

  test "bulk updates can run with nothing in the table" do
    Api.bulk_update!(Post, :update, %{title: "new_title"})
  end

  test "bulk updates update everything pertaining to the query" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Api.bulk_update!(Post, :update, %{},
      atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")}
    )

    posts = Api.read!(Post)
    assert Enum.all?(posts, &String.ends_with?(&1.title, "_stuff"))
  end

  test "bulk updates only apply to things that the query produces" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(title == "fred")
    |> Api.bulk_update!(:update, %{}, atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")})

    titles =
      Post
      |> Api.read!()
      |> Enum.map(& &1.title)
      |> Enum.sort()

    assert titles == ["fred_stuff", "george"]
  end

  test "bulk updates can be done even on stream inputs" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Api.read!()
    |> Api.bulk_update!(:update, %{},
      atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")},
      return_records?: true
    )

    titles =
      Post
      |> Api.read!()
      |> Enum.map(& &1.title)
      |> Enum.sort()

    assert titles == ["fred_stuff", "george_stuff"]
  end
end
