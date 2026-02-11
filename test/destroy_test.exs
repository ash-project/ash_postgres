# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.DestroyTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Post, Permalink}

  test "destroy with restrict on_delete returns would leave records behind error" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    Permalink |> Ash.Changeset.for_create(:create, %{post_id: post.id}) |> Ash.create!()

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             post
             |> Ash.Changeset.for_destroy(:destroy, %{})
             |> Ash.destroy()

    assert Enum.any?(errors, fn
             %Ash.Error.Changes.InvalidAttribute{message: msg} ->
               msg =~ "would leave records behind"

             _ ->
               false
           end),
           "Expected 'would leave records behind' error, got: #{inspect(errors)}"
  end

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
