# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ParentFilterTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Comment, Organization, Post, User}

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

  test "aggregates from related filters are properly added to the query" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "test_org"})
      |> Ash.create!()

    post_in_my_org =
      Post
      |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, title: "test_org"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "test_org"})
    |> Ash.Changeset.manage_relationship(:post, post_in_my_org, type: :append_and_remove)
    |> Ash.create!()

    assert {:ok, _} =
             Post
             |> Ash.Query.for_read(:read)
             |> Ash.Query.filter(
               organizations_with_posts_that_have_the_post_title_somewhere_in_their_comments.name in [
                 ^organization.name
               ]
             )
             |> Ash.read(authorize?: false)
  end
end
