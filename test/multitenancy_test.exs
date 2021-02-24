defmodule AshPostgres.Test.MultitenancyTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.MultitenancyTest.{Api, Org, Post}

  setup do
    org1 =
      Org
      |> Ash.Changeset.new(name: "test1")
      |> Api.create!()

    org2 =
      Org
      |> Ash.Changeset.new(name: "test2")
      |> Api.create!()

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
             |> Api.read!()
  end

  test "attribute multitenancy is set on creation" do
    uuid = Ash.UUID.generate()

    org =
      Org
      |> Ash.Changeset.new(name: "test3")
      |> Ash.Changeset.set_tenant("org_#{uuid}")
      |> Api.create!()

    assert org.id == uuid
  end

  test "schema multitenancy works", %{org1: org1, org2: org2} do
    Post
    |> Ash.Changeset.new(name: "foo")
    |> Ash.Changeset.set_tenant(tenant(org1))
    |> Api.create!()

    assert [_] = Post |> Ash.Query.set_tenant(tenant(org1)) |> Api.read!()
    assert [] = Post |> Ash.Query.set_tenant(tenant(org2)) |> Api.read!()
  end

  test "schema rename on update works", %{org1: org1} do
    new_uuid = Ash.UUID.generate()

    org1
    |> Ash.Changeset.new(id: new_uuid)
    |> Api.update!()

    new_tenant = "org_#{new_uuid}"

    assert {:ok, %{rows: [[^new_tenant]]}} =
             Ecto.Adapters.SQL.query(
               AshPostgres.TestRepo,
               """
               SELECT schema_name FROM information_schema.schemata WHERE schema_name = '#{
                 new_tenant
               }';
               """
             )
  end

  test "unique constraints are properly scoped", %{org1: org1} do
    post =
      Post
      |> Ash.Changeset.new(%{})
      |> Ash.Changeset.set_tenant(tenant(org1))
      |> Api.create!()

    assert_raise Ash.Error.Invalid,
                 ~r/Invalid value provided for id: has already been taken/,
                 fn ->
                   Post
                   |> Ash.Changeset.new(%{id: post.id})
                   |> Ash.Changeset.set_tenant(tenant(org1))
                   |> Api.create!()
                 end
  end
end
