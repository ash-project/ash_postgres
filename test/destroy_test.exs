defmodule AshPostgres.DestroyTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  test "destroy action destroys the record" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    post
    |> Ash.Changeset.for_destroy(:destroy, %{})
    |> Ash.destroy!()

    assert [] = Ash.read!(Post)
  end

  test "before action hooks are honored" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/must type CONFIRM/, fn ->
      post
      |> Ash.Changeset.for_destroy(:destroy_with_confirm, %{confirm: "NOT CONFIRM"})
      |> Ash.destroy!()
    end
  end

  test "before action hooks are honored, for soft destroys as well" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/must type CONFIRM/, fn ->
      post
      |> Ash.Changeset.for_destroy(:soft_destroy_with_confirm, %{confirm: "NOT CONFIRM"})
      |> Ash.destroy!()
    end
  end

  test "can optimistic lock" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
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
      |> Ash.Changeset.for_destroy(
        :optimistic_lock_destroy,
        %{}
      )
      |> Ash.destroy!()
    end
  end
end
