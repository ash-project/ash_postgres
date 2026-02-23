# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.SchemaTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Author, Profile}

  require Ash.Query

  setup do
    [author: Ash.create!(Ash.Changeset.for_create(Author, :create, %{}))]
  end

  test "data can be created", %{author: author} do
    assert %{description: "foo"} =
             Profile
             |> Ash.Changeset.for_create(:create, %{description: "foo"})
             |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
             |> Ash.create!()
  end

  test "data can be read", %{author: author} do
    Profile
    |> Ash.Changeset.for_create(:create, %{description: "foo"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert [%{description: "foo"}] = Profile |> Ash.read!()
  end

  test "they can be filtered across", %{author: author} do
    profile =
      Profile
      |> Ash.Changeset.for_create(:create, %{description: "foo"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    Ash.create!(Ash.Changeset.for_create(Author, :create, %{}))

    assert [_] =
             Author
             |> Ash.Query.filter(profile.id == ^profile.id)
             |> Ash.read!()

    assert [_] =
             Profile
             |> Ash.Query.filter(author.id == ^author.id)
             |> Ash.read!()
  end

  test "aggregates work across schemas", %{author: author} do
    Profile
    |> Ash.Changeset.for_create(:create, %{description: "foo"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert [%{profile_description: "foo"}] =
             Author
             |> Ash.Query.filter(profile_description == "foo")
             |> Ash.Query.load(:profile_description)
             |> Ash.read!()

    assert %{profile_description: "foo"} = Ash.load!(author, :profile_description)
  end
end
