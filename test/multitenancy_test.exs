defmodule AshPostgres.Test.MultitenancyTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.MultitenancyTest.{Org, Post, User}

  setup do
    org1 =
      Org
      |> Ash.Changeset.for_create(:create, %{name: "test1"})
      |> Ash.create!()

    org2 =
      Org
      |> Ash.Changeset.for_create(:create, %{name: "test2"})
      |> Ash.create!()

    [org1: org1, org2: org2]
  end

  defp tenant(org) do
    "org_#{org.id}"
  end

  test "listing tenants", %{org1: org1, org2: org2} do
    tenant_ids =
      [org1, org2]
      |> Enum.map(&tenant/1)
      |> Enum.sort()

    assert Enum.sort(AshPostgres.TestRepo.all_tenants()) == tenant_ids
  end

  test "attribute multitenancy works", %{org1: %{id: org_id} = org1} do
    assert [%{id: ^org_id}] =
             Org
             |> Ash.Query.set_tenant(tenant(org1))
             |> Ash.read!()
  end

  test "context multitenancy works with policies", %{org1: org1} do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{name: "foo"}, tenant: tenant(org1))
      |> Ash.create!()

    post
    |> Ash.Changeset.for_update(:update_with_policy, %{}, authorize?: true, tenant: tenant(org1))
    |> Ash.update!()
  end

  test "attribute multitenancy is set on creation" do
    uuid = Ash.UUID.generate()

    org =
      Org
      |> Ash.Changeset.for_create(:create, %{name: "test3"})
      |> Ash.Changeset.set_tenant("org_#{uuid}")
      |> Ash.create!()

    assert org.id == uuid
  end

  test "schema multitenancy works", %{org1: org1, org2: org2} do
    Post
    |> Ash.Changeset.for_create(:create, %{name: "foo"})
    |> Ash.Changeset.set_tenant(tenant(org1))
    |> Ash.create!()

    assert [_] = Post |> Ash.Query.set_tenant(tenant(org1)) |> Ash.read!()
    assert [] = Post |> Ash.Query.set_tenant(tenant(org2)) |> Ash.read!()
  end

  test "schema rename on update works", %{org1: org1} do
    new_uuid = Ash.UUID.generate()

    org1
    |> Ash.Changeset.for_update(:update, %{id: new_uuid})
    |> Ash.update!()

    new_tenant = "org_#{new_uuid}"

    assert {:ok, %{rows: [[^new_tenant]]}} =
             Ecto.Adapters.SQL.query(
               AshPostgres.TestRepo,
               """
               SELECT schema_name FROM information_schema.schemata WHERE schema_name = '#{new_tenant}';
               """
             )
  end

  test "loading attribute multitenant resources from context multitenant resources works" do
    org =
      Org
      |> Ash.Changeset.new()
      |> Ash.create!()

    user =
      User
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    assert Ash.load!(user, :org).org.id == org.id
  end

  test "loading context multitenant resources from attribute multitenant resources works" do
    org =
      Org
      |> Ash.Changeset.new()
      |> Ash.create!()

    user1 =
      User
      |> Ash.Changeset.for_create(:create, %{name: "a"})
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    user2 =
      User
      |> Ash.Changeset.for_create(:create, %{name: "b"})
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    user1_id = user1.id
    user2_id = user2.id

    assert [%{id: ^user1_id}, %{id: ^user2_id}] =
             Ash.load!(org, users: Ash.Query.sort(User, :name)).users
  end

  test "manage_relationship from context multitenant resource to attribute multitenant resource doesn't raise an error" do
    org = Org |> Ash.Changeset.new() |> Ash.create!()
    user = User |> Ash.Changeset.new() |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{}, tenant: tenant(org))
    |> Ash.Changeset.manage_relationship(:user, user, type: :append_and_remove)
    |> Ash.create!()
  end

  test "loading attribute multitenant resources with limits from context multitenant resources works" do
    org =
      Org
      |> Ash.Changeset.new()
      |> Ash.create!()

    user =
      User
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    assert Ash.load!(user, :org).org.id == org.id
  end

  test "loading context multitenant resources with limits from attribute multitenant resources works" do
    org =
      Org
      |> Ash.Changeset.new()
      |> Ash.create!()

    user1 =
      User
      |> Ash.Changeset.for_create(:create, %{name: "a"})
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    user2 =
      User
      |> Ash.Changeset.for_create(:create, %{name: "b"})
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    user1_id = user1.id
    user2_id = user2.id

    assert [%{id: ^user1_id}, %{id: ^user2_id}] =
             Ash.load!(org, users: Ash.Query.sort(Ash.Query.limit(User, 10), :name)).users
  end

  test "unique constraints are properly scoped", %{org1: org1} do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.Changeset.set_tenant(tenant(org1))
      |> Ash.create!()

    assert_raise Ash.Error.Invalid,
                 ~r/Invalid value provided for id: has already been taken/,
                 fn ->
                   Post
                   |> Ash.Changeset.for_create(:create, %{id: post.id})
                   |> Ash.Changeset.set_tenant(tenant(org1))
                   |> Ash.create!()
                 end
  end
end
