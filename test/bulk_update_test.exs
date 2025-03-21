defmodule AshPostgres.BulkUpdateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{CSV, Post, Record}

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

  @tag :regression
  test "bulk updates can update maps with the join strategy" do
    Post
    |> Ash.Query.limit(1)
    |> Ash.Query.filter(exists(comments, title == parent(title)))
    |> Ash.bulk_update!(:update_metadata, %{metadata: %{1 => 2}})
  end

  test "bulk updates can set datetimes" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "fred"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "george"})
    |> Ash.create!()

    now = DateTime.utc_now()

    Ash.bulk_update!(Post, :update, %{datetime: now}, strategy: :atomic)

    posts = Ash.read!(Post)

    assert Enum.all?(posts, fn post ->
             DateTime.compare(post.datetime, now) == :eq
           end)

    assert Enum.all?(posts, fn post ->
             DateTime.diff(now, post.updated_at, :minute) < 1
           end)
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

  test "bulk updates honor update action filters" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.bulk_update!(:update_only_freds, %{},
      return_errors?: true,
      atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")}
    )

    titles =
      Post
      |> Ash.read!()
      |> Enum.map(& &1.title)
      |> Enum.sort()

    assert titles == ["fred_stuff", "george"]
  end

  test "bulk updates honor update action filters when streaming" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.bulk_update!(:update_only_freds, %{},
      strategy: :stream,
      return_errors?: true,
      atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")}
    )

    posts =
      Post
      |> Ash.read!()

    fred =
      posts
      |> Enum.find(&(&1.title == "fred_stuff"))

    assert fred.created_at != fred.updated_at

    titles =
      posts
      |> Enum.map(& &1.title)
      |> Enum.sort()

    assert titles == ["fred_stuff", "george"]
  end

  test "errors in streaming bulk updates that would result in rollbacks are handled" do
    Ash.bulk_create!(
      [
        %{uniq_custom_one: "fred", uniq_custom_two: "weasley1"},
        %{uniq_custom_one: "fred", uniq_custom_two: "weasley2"}
      ],
      Post,
      :create,
      return_records?: true
    )

    assert %Ash.BulkResult{errors: [%Ash.Error.Invalid{}]} =
             Post
             |> Ash.bulk_update(:update, %{uniq_custom_two: "weasley"},
               strategy: :stream,
               return_errors?: true
             )
  end

  test "bulk updates can be limited" do
    Ash.bulk_create!([%{title: "fred"}, %{title: "george"}], Post, :create)

    Post
    |> Ash.Query.limit(1)
    |> Ash.Query.sort(:title)
    |> Ash.bulk_update!(:dont_validate, %{},
      atomic_update: %{title: Ash.Expr.expr(title <> "_stuff")},
      strategy: :atomic
    )

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
      |> Ash.Query.for_read(:paginated, %{}, authorize?: true)
      |> Ash.bulk_update!(:requires_initial_data, %{},
        authorize?: true,
        allow_stream_with: :full_read,
        authorize_query?: false,
        return_errors?: true,
        return_records?: true
      )
    end
  end

  test "bulk updates return error for null value if allow_nil? false with strategy :stream" do
    Ash.bulk_create!([%{full_name: "foo"}], Record, :create)

    assert %Ash.BulkResult{
             error_count: 1,
             errors: [
               %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :full_name}]}
             ]
           } =
             Ash.bulk_update(Record, :update, %{full_name: ""},
               strategy: :stream,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
  end

  test "bulk updates return error for null value if allow_nil? false with strategy :atomic" do
    Ash.bulk_create!([%{full_name: "foo"}], Record, :create)

    assert %Ash.BulkResult{
             error_count: 1,
             errors: [
               %Ash.Error.Invalid{errors: [%Ash.Error.Changes.Required{field: :full_name}]}
             ]
           } =
             Ash.bulk_update(Record, :update, %{full_name: ""},
               strategy: :atomic,
               return_records?: true,
               return_errors?: true,
               authorize?: false
             )
  end

  @tag :regression
  test "jsonb[] attribute with embedded Resource definition can be created and updated" do
    %{status: :success} =
      Ash.bulk_create!(
        [%{column_mapping_embedded: [%{column: 1, attribute: "foo"}]}],
        CSV,
        :create,
        return_records?: true,
        return_errors?: true
      )

    Ash.bulk_update!(CSV, :update, %{
      column_mapping_embedded: [%{column: 1, attribute: "foo"}],
      column_mapping_new_type: [%{column: 1, attribute: "foo"}]
    })
  end
end
