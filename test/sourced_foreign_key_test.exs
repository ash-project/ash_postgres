# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.SourcedForeignKeyTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{SourcedFkChild, SourcedFkParent}

  test "creating a child with a nonexistent parent returns an invalid error when the fk attribute has a different source" do
    assert {:error, %Ash.Error.Invalid{}} =
             SourcedFkChild
             |> Ash.Changeset.for_create(:create, %{parent_ref: Ash.UUID.generate()})
             |> Ash.create()
  end

  test "destroying a parent with children returns the reference's on_delete_message when the fk attribute has a different source" do
    parent = Ash.create!(SourcedFkParent, %{})
    Ash.create!(SourcedFkChild, %{parent_ref: parent.id})

    assert {:error, %Ash.Error.Invalid{errors: errors}} = Ash.destroy(parent)

    assert Enum.any?(errors, fn
             %Ash.Error.Changes.InvalidAttribute{message: "parent still has children"} -> true
             _ -> false
           end),
           "Expected custom on_delete_message, got: #{inspect(errors)}"
  end

  test "updating a referenced parent attribute returns the reference's on_update_message" do
    parent = Ash.create!(SourcedFkParent, %{})
    Ash.create!(SourcedFkChild, %{parent_ref: parent.id})

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             parent
             |> Ash.Changeset.for_update(:update, %{id: Ash.UUID.generate()})
             |> Ash.update()

    assert Enum.any?(errors, fn
             %Ash.Error.Changes.InvalidAttribute{
               message: "parent is still referenced by children"
             } ->
               true

             _ ->
               false
           end),
           "Expected custom on_update_message, got: #{inspect(errors)}"
  end
end
