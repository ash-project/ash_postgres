defmodule AshPostgres.BulkDestroyTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Permalink
  alias AshPostgres.Test.Post

  require Ash.Expr
  require Ash.Query

  test "bulk destroys can run with nothing in the table" do
    Ash.bulk_destroy!(Post, :destroy, %{})
  end

  test "bulk destroys destroy everything pertaining to the query" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Ash.bulk_destroy!(Post, :destroy, %{})

    assert Ash.read!(Post) == []
  end

  test "bulk destroys only apply to things that the query produces" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(title == "fred")
    |> Ash.bulk_destroy!(:destroy, %{})

    # 😢 sad
    assert ["george"] = Ash.read!(Post) |> Enum.map(& &1.title)
  end

  test "bulk destroys honor changeset filters" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.bulk_destroy!(:destroy_only_freds, %{})

    # 😢 sad
    assert ["george"] = Ash.read!(Post) |> Enum.map(& &1.title)
  end

  test "bulk destroys honor changeset filters when streaming" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.bulk_destroy!(:destroy_only_freds, %{}, strategy: :stream)

    # 😢 sad
    assert ["george"] = Ash.read!(Post) |> Enum.map(& &1.title)
  end

  test "the query can join to related tables when necessary" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.filter(author.first_name == "fred" or title == "fred")
    |> Ash.Query.select([:title])
    |> Ash.bulk_destroy!(:destroy, %{}, return_records?: true)

    assert [%{title: "george"}] = Ash.read!(Post)
  end

  test "bulk destroys can be done even on stream inputs" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.read!()
    |> Ash.bulk_destroy!(:destroy, %{}, strategy: :stream, return_errors?: true)

    assert [] = Ash.read!(Post)
  end

  test "bulk destroys errors on constraint violation" do
    post = Ash.create!(Post, %{title: "fred"})
    Ash.create!(Permalink, %{post_id: post.id})

    assert %Ash.BulkResult{
             status: :error,
             error_count: 1,
             errors: [%Ash.Error.Invalid{}]
           } =
             Post
             |> Ash.read!()
             |> Ash.bulk_destroy(:destroy, %{},
               return_records?: true,
               return_errors?: true
             )
  end

  test "bulk destroys returns error on constraint violation with strategy stream" do
    post = Ash.create!(Post, %{title: "fred"})
    Ash.create!(Permalink, %{post_id: post.id})

    assert %Ash.BulkResult{
             status: :error,
             error_count: 1,
             errors: [%Ash.Error.Invalid{}]
           } =
             Post
             |> Ash.read!()
             |> Ash.bulk_destroy(:destroy, %{},
               strategy: :stream,
               return_records?: true,
               return_errors?: true
             )
  end
end
