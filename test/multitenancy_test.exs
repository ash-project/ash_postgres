defmodule AshPostgres.Test.MultitenancyTest do
  use AshPostgres.RepoCase, async: false

  require Ash.Query
  alias AshPostgres.MultitenancyTest.{CompositeKeyPost, NamedOrg, Org, Post, User, CompositeKeyPost}
  alias AshPostgres.Test.Post, as: GlobalPost

  setup do
    org1 =
      Org
      |> Ash.Changeset.for_create(:create, %{name: "test1"}, authorize?: false)
      |> Ash.create!()

    org2 =
      Org
      |> Ash.Changeset.for_create(:create, %{name: "test2"}, authorize?: false)
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

  test "lateral joining attribute multitenancy to context multitenancy works", %{org1: org1} do
    Org
    |> Ash.Query.for_read(:read, %{}, tenant: org1)
    |> Ash.Query.load(posts: Ash.Query.limit(Post, 2))
    |> Ash.read!()
  end

  test "attribute multitenancy works", %{org1: %{id: org_id} = org1} do
    assert [%{id: ^org_id}] =
             Org
             |> Ash.Query.set_tenant(org1)
             |> Ash.read!()
  end

  test "joining to non multitenant through relationship works", %{org1: org1} do
    Post
    |> Ash.Query.filter(linked_non_multitenant_posts.title == "fred")
    |> Ash.Query.set_tenant("org_" <> org1.id)
    |> Ash.read!()
  end

  test "joining from non multitenant through relationship works", %{org1: org1} do
    GlobalPost
    |> Ash.Query.filter(linked_multitenant_posts.name == "fred")
    |> Ash.Query.set_tenant("org_" <> org1.id)
    |> Ash.read!()
  end

  test "attribute multitenancy works with authorization", %{org1: org1} do
    user =
      User
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:org, org1, type: :append_and_remove)
      |> Ash.create!()

    assert [] =
             Org
             |> Ash.Query.set_tenant("org_" <> org1.id)
             |> Ash.Query.for_read(:has_policies, %{}, actor: user, authorize?: true)
             |> Ash.read!()
  end

  test "context multitenancy works with policies", %{org1: org1} do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{name: "foo"}, tenant: org1)
      |> Ash.create!()

    post
    |> Ash.Changeset.for_update(:update_with_policy, %{}, authorize?: true, tenant: org1)
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
    |> Ash.Changeset.set_tenant(org1)
    |> Ash.create!()

    assert [_] = Post |> Ash.Query.set_tenant(org1) |> Ash.read!()
    assert [] = Post |> Ash.Query.set_tenant(org2) |> Ash.read!()
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

  test "composite key multitenancy works", %{org1: org1} do
    CompositeKeyPost
    |> Ash.Changeset.for_create(:create, %{title: "foo"})
    |> Ash.Changeset.manage_relationship(:org, org1, type: :append_and_remove)
    |> Ash.Changeset.set_tenant(org1)
    |> Ash.create!()

    assert [_] = CompositeKeyPost |> Ash.Query.set_tenant(org1) |> Ash.read!()
  end

  test "composite key multitenancy works", %{org1: org1} do
    CompositeKeyPost
    |> Ash.Changeset.for_create(:create, %{title: "foo"})
    |> Ash.Changeset.set_tenant(org1)
    |> Ash.create!()

    assert [_] = CompositeKeyPost |> Ash.Query.set_tenant(org1) |> Ash.read!()
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

    user =
      User
      |> Ash.Changeset.for_create(:create, %{name: "a"}, tenant: "org_#{org.id}")
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    user2 =
      User
      |> Ash.Changeset.for_create(:create, %{name: "a"}, tenant: "org_#{org.id}")
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{name: "foobar"},
        authorize?: false,
        tenant: "org_#{org.id}"
      )
      |> Ash.Changeset.manage_relationship(:user, user, type: :append_and_remove)
      |> Ash.create!()

    post_id = post.id

    assert [%{posts: [%{id: ^post_id}]}, _] =
             Ash.load!([user, user2], [posts: Ash.Query.limit(Post, 2)],
               tenant: "org_#{org.id}",
               authorize?: false
             )
  end

  test "loading context multitenant resources across a many-to-many with a limit works" do
    org =
      Org
      |> Ash.Changeset.new()
      |> Ash.create!()

    user =
      User
      |> Ash.Changeset.for_create(:create, %{name: "a"}, tenant: "org_#{org.id}")
      |> Ash.Changeset.manage_relationship(:org, org, type: :append_and_remove)
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{name: "foobar"},
        authorize?: false,
        tenant: "org_#{org.id}"
      )
      |> Ash.Changeset.manage_relationship(:user, user, type: :append_and_remove)
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{name: "foobar"},
        authorize?: false,
        tenant: "org_#{org.id}"
      )
      |> Ash.Changeset.manage_relationship(:user, user, type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:linked_posts, post, type: :append_and_remove)
      |> Ash.create!()

    post_id = post.id

    assert [%{linked_posts: [%{id: ^post_id}]}, _] =
             Ash.load!([post2, post], [linked_posts: Ash.Query.limit(Post, 2)],
               tenant: "org_#{org.id}",
               authorize?: false
             )
  end

  test "manage_relationship from context multitenant resource to attribute multitenant resource doesn't raise an error" do
    org = Org |> Ash.Changeset.new() |> Ash.create!()
    user = User |> Ash.Changeset.new() |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{}, tenant: org)
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
      |> Ash.Changeset.set_tenant(org1)
      |> Ash.create!()

    assert_raise Ash.Error.Invalid,
                 ~r/Invalid value provided for id: has already been taken/,
                 fn ->
                   Post
                   |> Ash.Changeset.for_create(:create, %{id: post.id})
                   |> Ash.Changeset.set_tenant(org1)
                   |> Ash.create!()
                 end
  end

  test "rejects characters other than alphanumericals, - and _ on tenant creation" do
    assert_raise(
      Ash.Error.Unknown,
      ~r/Tenant name must match ~r\/\^\[a-zA-Z0-9_-]\+\$\/, got:/,
      fn ->
        NamedOrg
        |> Ash.Changeset.for_create(:create, %{name: "🚫"})
        |> Ash.create!()
      end
    )
  end

  test "rejects characters other than alphanumericals, - and _ when renaming tenant" do
    org =
      NamedOrg
      |> Ash.Changeset.for_create(:create, %{name: "toto"})
      |> Ash.create!()

    assert_raise(
      Ash.Error.Unknown,
      ~r/Tenant name must match ~r\/\^\[a-zA-Z0-9_-]\+\$\/, got:/,
      fn ->
        org
        |> Ash.Changeset.for_update(:update, %{name: "🚫"})
        |> Ash.update!()
      end
    )
  end
end
