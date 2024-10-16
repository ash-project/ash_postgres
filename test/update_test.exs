defmodule AshPostgres.UpdateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post
  require Ash.Query

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
    |> IO.inspect()

    assert is_nil(post.author)
  end
end
