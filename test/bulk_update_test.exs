defmodule AshPostgres.BulkUpdateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Expr
  require Ash.Query

  test "bulk updates can run with nothing in the table" do
    Ash.bulk_update!(Post, :update, %{title: "new_title"})
  end

  test "bulk updates update everything pertaining to the query" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Ash.bulk_update!(Post, :update, %{},
      atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")}
    )

    posts = Ash.read!(Post)
    assert Enum.all?(posts, &String.ends_with?(&1.title, "_stuff"))
  end

  test "a map can be given as input" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.bulk_update!(
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
      Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create,
        return_records?: true
      )

    post
    |> Ash.Changeset.for_update(:update, %{list_of_stuff: [%{a: [:a, :b]}, %{a: [:c, :d]}]})
    |> Ash.update!()
  end

  test "bulk updates only apply to things that the query produces" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(title == "fred")
    |> Ash.bulk_update!(:update, %{}, atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")})

    titles =
      Post
      |> Ash.read!()
      |> Enum.map(& &1.title)
      |> Enum.sort()

    assert titles == ["fred_stuff", "george"]
  end

  test "the query can join to related tables when necessary" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(author.first_name == "fred" or title == "fred")
    |> Ash.bulk_update!(:update, %{}, atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")})

    titles =
      Post
      |> Ash.read!()
      |> Enum.map(& &1.title)
      |> Enum.sort()

    assert titles == ["fred_stuff", "george"]
  end

  test "bulk updates can be done even on stream inputs" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.read!()
    |> Ash.bulk_update!(:update, %{},
      atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")},
      return_records?: true,
      strategy: [:stream]
    )

    titles =
      Post
      |> Ash.read!()
      |> Enum.map(& &1.title)
      |> Enum.sort()

    assert titles == ["fred_stuff", "george_stuff"]
  end

  test "bulk updates that require initial data must use streaming" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    assert_raise Ash.Error.Invalid, ~r/had no matching bulk strategy that could be used/, fn ->
      Post
      |> Ash.Query.for_read(:paginated, authorize?: true)
      |> Ash.bulk_update!(:requires_initial_data, %{},
        authorize?: true,
        allow_stream_with: :full_read,
        authorize_query?: false,
        return_errors?: true
      )
    end
  end
end
