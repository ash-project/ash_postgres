defmodule AshPostgresTest do
  use AshPostgres.RepoCase, async: false

  test "transaction metadata is given to on_transaction_begin" do
    AshPostgres.Test.Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert_receive %{
      type: :create,
      metadata: %{action: :create, actor: nil, resource: AshPostgres.Test.Post}
    }
  end

  test "filter policies are applied in create" do
    assert_raise Ash.Error.Forbidden, fn ->
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{title: "worst"})
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

    # post
    # |> Ash.Changeset.for_update(:update, %{title: "okay"}, authorize?: true)
    # |> Ash.update!()
    # |> Map.get(:title)
  end
end
