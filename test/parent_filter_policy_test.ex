defmodule ParentFilterPolicyTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Organization, Post, User}

  require Ash.Query

  test "building references don't throw an exception when doing weird things" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "test_org"})
      |> Ash.create!()

    user =
      User
      |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, name: "foo bar"})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, title: "test_org"})
    |> Ash.create!()

    assert {:ok, _results} =
             Post
             |> Ash.Query.for_read(:weird)
             |> Ash.read(
               authorize?: true,
               actor: user
             )
  end
end
