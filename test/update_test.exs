# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.UpdateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Permalink, Post}
  require Ash.Query
  import ExUnit.CaptureLog
  import Ash.Expr

  test "updating a referenced attribute returns would leave records behind error" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    Permalink |> Ash.Changeset.for_create(:create, %{post_id: post.id}) |> Ash.create!()

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             post
             |> Ash.Changeset.for_update(:update, %{id: Ash.UUID.generate()})
             |> Ash.update()

    assert Enum.any?(errors, fn
             %Ash.Error.Changes.InvalidAttribute{message: msg} ->
               msg =~ "would leave records behind"

             _ ->
               false
           end),
           "Expected 'would leave records behind' error, got: #{inspect(errors)}"
  end

  test "can update a keyword type attribute" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "keyword test"})
      |> Ash.create!()

    updated =
      post
      |> Ash.Changeset.for_update(:update, %{keyword_map: [display_template: "{{foo}}"]})
      |> Ash.update!()

    assert updated.keyword_map == [display_template: "{{foo}}"]
  end

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

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "fred"})
      |> Ash.create!()

    post
    |> Ash.Changeset.for_update(
      :optimistic_lock,
      %{
        title: "george"
      }
    )
    |> Ash.update!()

    assert_raise Ash.Error.Invalid, ~r/Attempted to update stale record/, fn ->
      post
      |> Ash.Changeset.for_update(
        :optimistic_lock,
        %{
          title: "harry"
        }
      )
      |> Ash.update!()
    end
  end

  test "absent validations behave the same atomically and non-atomically" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/must be absent/, fn ->
      Ash.update!(post, %{title: "title"}, action: :validate_absent_non_atomically)
    end

    assert_raise Ash.Error.Invalid, ~r/must be absent/, fn ->
      Ash.update!(post, %{}, action: :validate_absent_non_atomically)
    end

    assert_raise Ash.Error.Invalid, ~r/must be absent/, fn ->
      Ash.update!(post, %{title: "title"}, action: :validate_absent)
    end

    assert_raise Ash.Error.Invalid, ~r/must be absent/, fn ->
      Ash.update!(post, %{}, action: :validate_absent)
    end
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

  test "queries are run if there are no changes but the action adds filters atomically" do
    post =
      AshPostgres.Test.IntegerPost
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/stale/, fn ->
      post
      |> Ash.Changeset.for_update(:update_only_freds, %{})
      |> Ash.update!()
    end
  end

  describe "a changeset filter that joins a sorted to-one relationship" do
    setup do
      post = Ash.Seed.seed!(Post, %{title: "match"})
      Ash.Seed.seed!(AshPostgres.Test.Comment, %{title: "match", post_id: post.id})

      %{post: post}
    end

    test "updates the record when it matches", %{post: post} do
      assert {:ok, %{title: "new"}} =
               post
               |> Ash.Changeset.for_update(:change_title, %{title: "new"}, authorize?: false)
               |> Ash.Changeset.filter(expr(latest_comment.title == "match"))
               |> Ash.update(authorize?: false)
    end

    test "returns a stale record error when it doesn't match", %{post: post} do
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
               post
               |> Ash.Changeset.for_update(:change_title, %{title: "new"}, authorize?: false)
               |> Ash.Changeset.filter(expr(latest_comment.title == "other"))
               |> Ash.update(authorize?: false)

      assert Ash.get!(Post, post.id, authorize?: false).title == "match"
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

  test "loaded relationships remain loaded after update" do
    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.for_create(:create, %{first_name: "foo", last_name: "bar"})
      |> Ash.create!()

    _post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "baz"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    author = author |> Ash.load!(:posts)

    assert [%Post{}] = author.posts

    author = author |> Ash.Changeset.for_update(:update, %{first_name: "foo2"}) |> Ash.update!()

    assert [%Post{}] = author.posts
  end

  describe "manage_relationship from hooks on update" do
    test "before_transaction hook" do
      comment =
        AshPostgres.Test.Comment
        |> Ash.Changeset.for_create(:create, %{title: "test comment"})
        |> Ash.create!()

      assert comment.post_id == nil

      updated =
        comment
        |> Ash.Changeset.for_update(:update_with_post_from_before_transaction, %{})
        |> Ash.update!()

      assert updated.post_id != nil
      loaded = Ash.load!(updated, :post)
      assert loaded.post.title == "created-in-before-transaction"
    end

    test "before_action hook" do
      comment =
        AshPostgres.Test.Comment
        |> Ash.Changeset.for_create(:create, %{title: "test comment"})
        |> Ash.create!()

      assert comment.post_id == nil

      updated =
        comment
        |> Ash.Changeset.for_update(:update_with_post_from_before_action, %{})
        |> Ash.update!()

      assert updated.post_id != nil
      loaded = Ash.load!(updated, :post)
      assert loaded.post.title == "created-in-before-action"
    end

    test "before_transaction hook via bulk_update" do
      comment =
        AshPostgres.Test.Comment
        |> Ash.Changeset.for_create(:create, %{title: "test comment"})
        |> Ash.create!()

      assert comment.post_id == nil

      result =
        AshPostgres.Test.Comment
        |> Ash.Query.filter(id == ^comment.id)
        |> Ash.bulk_update!(:update_with_post_from_before_transaction, %{},
          strategy: :stream,
          return_records?: true,
          return_errors?: true
        )

      assert result.status == :success
      [updated] = result.records
      assert updated.post_id != nil
      loaded = Ash.load!(updated, :post)
      assert loaded.post.title == "created-in-before-transaction"
    end

    test "before_action hook via bulk_update" do
      comment =
        AshPostgres.Test.Comment
        |> Ash.Changeset.for_create(:create, %{title: "test comment"})
        |> Ash.create!()

      assert comment.post_id == nil

      result =
        AshPostgres.Test.Comment
        |> Ash.Query.filter(id == ^comment.id)
        |> Ash.bulk_update!(:update_with_post_from_before_action, %{},
          strategy: :stream,
          return_records?: true,
          return_errors?: true
        )

      assert result.status == :success
      [updated] = result.records
      assert updated.post_id != nil
      loaded = Ash.load!(updated, :post)
      assert loaded.post.title == "created-in-before-action"
    end
  end
end
