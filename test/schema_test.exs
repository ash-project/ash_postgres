defmodule AshPostgres.SchemaTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Author, Profile}

  require Ash.Query

  setup do
    [author: Api.create!(Ash.Changeset.for_create(Author, :create, %{}))]
  end

  test "data can be created", %{author: author} do
    assert %{description: "foo"} =
             Profile
             |> Ash.Changeset.for_create(:create, %{description: "foo"})
             |> Ash.Changeset.replace_relationship(:author, author)
             |> Api.create!()
  end

  test "data can be read", %{author: author} do
    Profile
    |> Ash.Changeset.for_create(:create, %{description: "foo"})
    |> Ash.Changeset.replace_relationship(:author, author)
    |> Api.create!()

    assert [%{description: "foo"}] = Profile |> Api.read!()
  end

  test "they can be filtered across", %{author: author} do
    profile =
      Profile
      |> Ash.Changeset.for_create(:create, %{description: "foo"})
      |> Ash.Changeset.replace_relationship(:author, author)
      |> Api.create!()

    Api.create!(Ash.Changeset.for_create(Author, :create, %{}))

    assert [_] =
             Author
             |> Ash.Query.filter(profile.id == ^profile.id)
             |> Api.read!()

    assert [_] =
             Profile
             |> Ash.Query.filter(author.id == ^author.id)
             |> Api.read!()
  end

  test "aggregates work across schemas", %{author: author} do
    Profile
    |> Ash.Changeset.for_create(:create, %{description: "foo"})
    |> Ash.Changeset.replace_relationship(:author, author)
    |> Api.create!()

    assert [%{profile_description: "foo"}] =
             Author
             |> Ash.Query.filter(profile_description == "foo")
             |> Api.read!()

    assert %{profile_description: "foo"} = Api.load!(author, :profile_description)
  end
end
