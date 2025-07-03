defmodule AshPostgres.Test.ParentFilterTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Organization, Post, User}

  require Ash.Query

  test "when the first relationship in an `exists` path has parent references in its filter, we don't get error" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "test_org"})
      |> Ash.create!()

    not_my_organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "test_org_2"})
      |> Ash.create!()

    user =
      User
      |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, name: "foo bar"})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: not_my_organization.id})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, title: "test_org"})
    |> Ash.create!()

    assert {:ok, [%Post{title: "test_org"}]} =
             Post
             |> Ash.Query.for_read(:read_with_policy_with_parent)
             |> Ash.read(
               authorize?: true,
               actor: user
             )

    assert {:ok, _} =
             Post
             |> Ash.Query.filter(
               organization.posts.posts_with_my_organization_name_as_a_title.title == "tuna"
             )
             |> Ash.read(authorize?: false)
  end
end
