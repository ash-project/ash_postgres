defmodule AshPostgresTest do
  use AshPostgres.RepoCase, async: false
  import ExUnit.CaptureLog

  test "transaction metadata is given to on_transaction_begin" do
    AshPostgres.Test.Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.Changeset.after_action(fn _, result ->
      {:ok, result}
    end)
    |> Ash.create!()

    assert_receive %{
      type: :create,
      metadata: %{action: :create, actor: nil, resource: AshPostgres.Test.Post}
    }
  end

  test "filter policies are applied in create" do
    assert_raise Ash.Error.Forbidden, fn ->
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "worst"}, authorize?: true)
      |> Ash.create!()
    end
  end

  test "filter policies are applied in update" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "good"})
      |> Ash.create!()

    assert_raise Ash.Error.Forbidden, fn ->
      post
      |> Ash.Changeset.for_update(:update, %{title: "bad"},
        authorize?: true,
        actor: nil,
        actor: %{id: Ash.UUID.generate()}
      )
      |> Ash.update!(
        authorize?: true,
        actor: nil
      )
      |> Map.get(:title)
    end
  end

  test "it does not run queries for exists/2 expressions that can be determined from loaded data" do
    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.for_create(:create, %{}, authorize?: false)
      |> Ash.create!()

    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "good", author_id: author.id})
      |> Ash.create!()
      |> Ash.load!(:author)

    log =
      capture_log(fn ->
        post
        |> Ash.Changeset.for_update(:update_if_author, %{title: "bad"},
          authorize?: true,
          actor: nil,
          actor: author
        )
        |> then(&AshPostgres.Test.Post.can_update_if_author?(author, &1, reuse_values?: true))
      end)

    assert log == ""
  end
end
