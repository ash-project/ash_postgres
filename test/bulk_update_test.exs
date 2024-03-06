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

  test "a map can be given as input" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Api.bulk_update!(
      :update,
      %{list_of_stuff: [%{a: 1}]},
      return_records?: true,
      strategy: [:atomic]
    )
    |> Map.get(:records)
    |> Enum.map(& &1.list_of_stuff)
  end

  test "a map can be given as input on a regular update" do
    %{records: [post | _]} =
      Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create,
        return_records?: true
      )

    post
    |> Ash.Changeset.for_update(:update, %{list_of_stuff: [%{a: [:a, :b]}, %{a: [:c, :d]}]})
    |> Api.update!()
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

  test "the query can join to related tables when necessary" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(author.first_name == "fred" or title == "fred")
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

  test "bulk updates that require initial data must use streaming" do
    Api.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.for_read(:paginated, authorize?: true)
    |> Api.bulk_update!(:requires_initial_data, %{},
      authorize?: true,
      allow_stream_with: :full_read,
      authorize_query?: false
    )
  end
end
