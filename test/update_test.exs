defmodule AshPostgres.UpdateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post
  require Ash.Query
  import ExUnit.CaptureLog
  import Ash.Expr

  test "can update with nested maps" do
    Post
    |> Ash.Changeset.for_create(:create, %{stuff: %{foo: %{bar: :baz}}})
    |> Ash.create!()
    |> then(fn record ->
      Ash.Query.filter(Post, id == ^record.id)
    end)
    |> Ash.bulk_update(
      :update,
      %{
        stuff: %{
          summary: %{
            chat_history: [
              %{"content" => "Default system prompt", "role" => "system"},
              %{
                "content" => "stuff",
                "role" => "user"
              },
              %{"content" => "test", "role" => "user"},
              %{
                "content" =>
                  "It looks like you're testing the feature. How can I assist you further?",
                "role" => "assistant"
              }
            ]
          }
        }
      }
    )
  end

  test "can optimistic lock" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "fred"})
    |> Ash.create!()
    |> then(fn record ->
      Ash.Query.filter(Post, id == ^record.id)
    end)
    |> Ash.bulk_update(
      :optimistic_lock,
      %{
        title: "george"
      }
    )

    Post
    |> Ash.Changeset.for_create(:create, %{title: "fred"})
    |> Ash.create!()
    |> Ash.Changeset.for_update(
      :optimistic_lock,
      %{
        title: "george"
      }
    )
    |> Ash.update!()
  end

  test "timestamps arent updated if there are no changes non-atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post2 =
      post
      |> Ash.update!(action: :change_nothing)

    assert post.updated_at == post2.updated_at
  end

  test "no queries are run if there are no changes non-atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    assert "" =
             capture_log(fn ->
               post
               |> Ash.update!(action: :change_nothing)
             end)
  end

  test "queries are run if there are no changes but there are filters non-atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/stale/, fn ->
      post
      |> Ash.Changeset.for_update(:change_nothing, %{})
      |> Ash.Changeset.filter(expr(title != "match"))
      |> Ash.update!(action: :change_nothing)
    end
  end

  test "timestamps arent updated if there are no changes atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post2 =
      post
      |> Ash.update!(action: :change_nothing_atomic)

    assert post.updated_at == post2.updated_at
  end

  test "timestamps arent updated if nothing changes non-atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post2 =
      post
      |> Ash.update!(%{title: "match"}, action: :change_title)

    assert post.updated_at == post2.updated_at
  end

  test "timestamps arent updated if nothing changes atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post2 =
      post
      |> Ash.update!(%{title: "match"}, action: :change_title_atomic)

    assert post.updated_at == post2.updated_at
  end

  test "queries are run if there are no changes atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/stale/, fn ->
      post
      |> Ash.Changeset.for_update(:change_nothing_atomic, %{})
      |> Ash.Changeset.filter(expr(title != "match"))
      |> Ash.update!(action: :change_nothing)
    end
  end

  test "can unrelate belongs_to" do
    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.for_create(:create, %{first_name: "is", last_name: "match"})
      |> Ash.create!()

    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    assert is_nil(post.author) == false

    post =
      post
      |> Ash.Changeset.for_update(:update)
      |> Ash.Changeset.manage_relationship(:author, author, type: :remove)
      |> Ash.update!()

    post
    |> Ash.load!(:author)
    |> Map.get(:author)

    assert is_nil(post.author)
  end
end
