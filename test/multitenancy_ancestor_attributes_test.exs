# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.MultitenancyAncestorAttributesTest do
  use AshPostgres.RepoCase, async: false

  require Ash.Query

  alias AshPostgres.MultitenancyTest.{DepartmentPost, DepartmentPostComment, DepartmentTenant}

  setup do
    organization_id = Ash.UUID.generate()
    other_organization_id = Ash.UUID.generate()
    department_a = %DepartmentTenant{id: Ash.UUID.generate(), organization_id: organization_id}
    department_b = %DepartmentTenant{id: Ash.UUID.generate(), organization_id: organization_id}

    # The discriminating tenant below reuses department_a's id under another
    # organization: the department filter alone matches, so only the ancestor
    # filter can tell them apart.
    wrong_organization_department = %DepartmentTenant{
      id: department_a.id,
      organization_id: other_organization_id
    }

    [
      organization_id: organization_id,
      department_a: department_a,
      department_b: department_b,
      wrong_organization_department: wrong_organization_department
    ]
  end

  test "create stamps the derived organization_id alongside the tenant's department_id", %{
    organization_id: organization_id,
    department_a: department_a
  } do
    post =
      DepartmentPost
      |> Ash.Changeset.for_create(:create, %{name: "post"}, tenant: department_a)
      |> Ash.create!()

    assert post.department_id == department_a.id
    assert post.organization_id == organization_id
  end

  test "a tenant with the same department id but another organization reads nothing", %{
    department_a: department_a,
    wrong_organization_department: wrong_organization_department
  } do
    post =
      DepartmentPost
      |> Ash.Changeset.for_create(:create, %{name: "post"}, tenant: department_a)
      |> Ash.create!()

    assert [%{id: read_id}] = DepartmentPost |> Ash.Query.set_tenant(department_a) |> Ash.read!()
    assert read_id == post.id

    assert [] =
             DepartmentPost |> Ash.Query.set_tenant(wrong_organization_department) |> Ash.read!()
  end

  test "update can't reach a row whose ancestors don't match the tenant", %{
    department_a: department_a,
    wrong_organization_department: wrong_organization_department
  } do
    post =
      DepartmentPost
      |> Ash.Changeset.for_create(:create, %{name: "before"}, tenant: department_a)
      |> Ash.create!()

    assert {:error, _} =
             post
             |> Ash.Changeset.for_update(:update, %{name: "after"},
               tenant: wrong_organization_department
             )
             |> Ash.update()

    assert [%{name: "before"}] =
             DepartmentPost |> Ash.Query.set_tenant(department_a) |> Ash.read!()
  end

  test "upsert conflict targets include the ancestor attributes and match the generated unique index",
       %{
         department_a: department_a,
         department_b: department_b
       } do
    # The unique index is (organization_id, department_id, name); without the
    # ancestor attributes in the conflict target, ON CONFLICT wouldn't match
    # any index and every upsert here would raise.
    department_a_post =
      DepartmentPost
      |> Ash.Changeset.for_create(:upsert_by_name, %{name: "same name"}, tenant: department_a)
      |> Ash.create!()

    department_b_post =
      DepartmentPost
      |> Ash.Changeset.for_create(:upsert_by_name, %{name: "same name"}, tenant: department_b)
      |> Ash.create!()

    refute department_b_post.id == department_a_post.id

    upserted =
      DepartmentPost
      |> Ash.Changeset.for_create(:upsert_by_name, %{name: "same name"}, tenant: department_a)
      |> Ash.create!()

    assert upserted.id == department_a_post.id
  end

  test "relationship loads and aggregates exclude a comment matching the department but not the organization",
       %{
         department_a: department_a,
         wrong_organization_department: wrong_organization_department
       } do
    post =
      DepartmentPost
      |> Ash.Changeset.for_create(:create, %{name: "post"}, tenant: department_a)
      |> Ash.create!()

    DepartmentPostComment
    |> Ash.Changeset.for_create(:create, %{text: "other organization", post_id: post.id},
      tenant: wrong_organization_department
    )
    |> Ash.create!()

    assert [%{comments: [], count_of_comments: 0}] =
             DepartmentPost
             |> Ash.Query.set_tenant(department_a)
             |> Ash.Query.load([:comments, :count_of_comments])
             |> Ash.read!()

    DepartmentPostComment
    |> Ash.Changeset.for_create(:create, %{text: "same tenant", post_id: post.id},
      tenant: department_a
    )
    |> Ash.create!()

    assert [%{comments: [%{text: "same tenant"}], count_of_comments: 1}] =
             DepartmentPost
             |> Ash.Query.set_tenant(department_a)
             |> Ash.Query.load([:comments, :count_of_comments])
             |> Ash.read!()
  end

  test "exists over a relationship excludes a comment matching the department but not the organization",
       %{
         department_a: department_a,
         wrong_organization_department: wrong_organization_department
       } do
    post =
      DepartmentPost
      |> Ash.Changeset.for_create(:create, %{name: "post"}, tenant: department_a)
      |> Ash.create!()

    DepartmentPostComment
    |> Ash.Changeset.for_create(:create, %{text: "comment", post_id: post.id},
      tenant: wrong_organization_department
    )
    |> Ash.create!()

    assert [] =
             DepartmentPost
             |> Ash.Query.set_tenant(department_a)
             |> Ash.Query.filter(exists(comments, text == "comment"))
             |> Ash.read!()

    DepartmentPostComment
    |> Ash.Changeset.for_create(:create, %{text: "comment", post_id: post.id},
      tenant: department_a
    )
    |> Ash.create!()

    assert [%{id: read_id}] =
             DepartmentPost
             |> Ash.Query.set_tenant(department_a)
             |> Ash.Query.filter(exists(comments, text == "comment"))
             |> Ash.read!()

    assert read_id == post.id
  end
end
