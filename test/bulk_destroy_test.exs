defmodule AshPostgres.BulkDestroyTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Expr
  require Ash.Query

  test "bulk destroys can run with nothing in the table" do
    Ash.bulk_destroy!(Post, :update, %{title: "new_title"})
  end

  test "bulk destroys destroy everything pertaining to the query" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Ash.bulk_destroy!(Post, :update, %{})

    assert Ash.read!(Post) == []
  end

  test "bulk destroys only apply to things that the query produces" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(title == "fred")
    |> Ash.bulk_destroy!(:update, %{})

    # 😢 sad
    assert [%{title: "george"}] = Ash.read!(Post)
  end

  test "the query can join to related tables when necessary" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(author.first_name == "fred" or title == "fred")
    |> Ash.bulk_destroy!(:update, %{}, return_records?: true)

    assert [%{title: "george"}] = Ash.read!(Post)
  end

  test "bulk destroys can be done even on stream inputs" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.read!()
    |> Ash.bulk_destroy!(:destroy, %{}, strategy: :stream, return_errors?: true)

    assert [] = Ash.read!(Post)
  end
end
