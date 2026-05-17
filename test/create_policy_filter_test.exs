# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CreatePolicyFilterTest do
  @moduledoc """
  Verifies the post-insert filter-policy-on-create deferral against a real
  transactional data layer. Covers three paths:

    * default `Ash.Policy.FilterCheck` returning a relationship-referencing
      filter — exercised via a single batched SELECT in the post-insert hook,
    * a custom `Ash.Policy.Check` returning `:unknown` from `auto_filter/3` —
      forcing the hook to delegate to `check/4`,
    * the combined policy where one branch is a filter and the other is a
      `:unknown`-deferred custom check.

  Each negative test also asserts the row does not survive the rejected create,
  which proves rollback fires inside the action transaction.
  """

  use AshPostgres.RepoCase, async: false
  require Ash.Query

  defmodule Domain do
    use Ash.Domain

    resources do
      allow_unregistered? true
    end
  end

  defmodule Organization do
    use Ash.Resource,
      domain: Domain,
      data_layer: AshPostgres.DataLayer

    postgres do
      table("create_policy_filter_orgs")
      repo(AshPostgres.TestRepo)
    end

    attributes do
      uuid_primary_key :id
      attribute :owner_id, :uuid, public?: true, allow_nil?: false
    end

    actions do
      default_accept :*
      defaults [:read, :destroy, create: :*, update: :*]
    end
  end

  defmodule Post do
    use Ash.Resource,
      domain: Domain,
      data_layer: AshPostgres.DataLayer,
      authorizers: [Ash.Policy.Authorizer]

    postgres do
      table("create_policy_filter_posts")
      repo(AshPostgres.TestRepo)
    end

    attributes do
      uuid_primary_key :id
      attribute :text, :string, public?: true, allow_nil?: false
    end

    relationships do
      belongs_to :organization, Organization,
        public?: true,
        attribute_writable?: true,
        allow_nil?: false
    end

    policies do
      policy action_type(:create) do
        authorize_if expr(organization.owner_id == ^actor(:id))
      end

      policy action_type(:read) do
        authorize_if always()
      end
    end

    actions do
      default_accept :*
      defaults [:read, :destroy, create: :*]
    end
  end

  defmodule CustomCheck do
    @moduledoc ~S"""
    Returns `:unknown` from `auto_filter/3` to force the framework into the
    post-insert `check/4` path. The check itself authorizes only when the
    inserted post's text matches `"ok-#{actor.id}"`.
    """
    use Ash.Policy.Check

    @impl true
    def describe(_), do: "custom check returning :unknown from auto_filter"

    @impl true
    def type, do: :filter

    @impl true
    def strict_check(_actor, _authorizer, _opts), do: {:ok, :unknown}

    @impl true
    def auto_filter(_actor, _authorizer, _opts), do: :unknown

    @impl true
    def check(actor, records, _authorizer, _opts) do
      send(self(), {:custom_check_invoked, length(records)})

      Enum.filter(records, fn record ->
        record.text == "ok-#{actor.id}"
      end)
    end
  end

  defmodule UnknownPost do
    use Ash.Resource,
      domain: Domain,
      data_layer: AshPostgres.DataLayer,
      authorizers: [Ash.Policy.Authorizer]

    postgres do
      table("create_policy_filter_posts")
      repo(AshPostgres.TestRepo)
    end

    attributes do
      uuid_primary_key :id
      attribute :text, :string, public?: true, allow_nil?: false
    end

    relationships do
      belongs_to :organization, Organization,
        public?: true,
        attribute_writable?: true,
        allow_nil?: false
    end

    policies do
      policy action_type(:create) do
        authorize_if {CustomCheck, []}
      end

      policy action_type(:read) do
        authorize_if always()
      end
    end

    actions do
      default_accept :*
      defaults [:read, :destroy, create: :*]
    end
  end

  defmodule MixedPost do
    @moduledoc """
    Combines two policies on create:

      * `forbid_unless expr(organization.owner_id == ^actor(:id))` —
        evaluated via the batched SELECT in the post-insert hook,
      * `authorize_if {CustomCheck, []}` — deferred to `check/4` via
        `:unknown` from `auto_filter/3`.

    Both must authorize the inserted record for the create to succeed; either
    rejecting on its own rolls back the transaction.
    """
    use Ash.Resource,
      domain: Domain,
      data_layer: AshPostgres.DataLayer,
      authorizers: [Ash.Policy.Authorizer]

    postgres do
      table("create_policy_filter_posts")
      repo(AshPostgres.TestRepo)
    end

    attributes do
      uuid_primary_key :id
      attribute :text, :string, public?: true, allow_nil?: false
    end

    relationships do
      belongs_to :organization, Organization,
        public?: true,
        attribute_writable?: true,
        allow_nil?: false
    end

    policies do
      policy action_type(:create) do
        forbid_unless expr(organization.owner_id == ^actor(:id))
        authorize_if {CustomCheck, []}
      end

      policy action_type(:read) do
        authorize_if always()
      end
    end

    actions do
      default_accept :*
      defaults [:read, :destroy, create: :*]
    end
  end

  setup do
    # The migration's "posts" table is shared by Post / UnknownPost / MixedPost
    # via the table option, so we just clean it (plus orgs) between tests.
    AshPostgres.TestRepo.query!("DELETE FROM create_policy_filter_posts", [])
    AshPostgres.TestRepo.query!("DELETE FROM create_policy_filter_orgs", [])
    :ok
  end

  describe "relationship-referencing filter check on create" do
    test "authorizes when the inserted record matches the filter (single SELECT)" do
      owner_id = Ash.UUID.generate()

      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{owner_id: owner_id})
        |> Ash.create!()

      assert {:ok, %Post{}} =
               Post
               |> Ash.Changeset.for_create(:create, %{text: "hi", organization_id: org.id})
               |> Ash.create(actor: %{id: owner_id})

      assert [_] = Ash.read!(Post, authorize?: false)
    end

    test "forbids and rolls back when the inserted record does not match the filter" do
      owner_id = Ash.UUID.generate()
      other_actor_id = Ash.UUID.generate()

      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{owner_id: owner_id})
        |> Ash.create!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Post
               |> Ash.Changeset.for_create(:create, %{text: "hi", organization_id: org.id})
               |> Ash.create(actor: %{id: other_actor_id})

      # Rollback: Postgres actually unwound the insert because the
      # forbidden response came from inside the action transaction.
      assert [] = Ash.read!(Post, authorize?: false)
    end
  end

  describe "auto_filter returning :unknown defers to check/4 post-insert" do
    test "authorizes when check/4 returns the inserted record" do
      actor_id = Ash.UUID.generate()

      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{owner_id: actor_id})
        |> Ash.create!()

      assert {:ok, %UnknownPost{}} =
               UnknownPost
               |> Ash.Changeset.for_create(:create, %{
                 text: "ok-#{actor_id}",
                 organization_id: org.id
               })
               |> Ash.create(actor: %{id: actor_id})

      assert_received {:custom_check_invoked, 1}
    end

    test "forbids and rolls back when check/4 returns no records" do
      actor_id = Ash.UUID.generate()

      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{owner_id: actor_id})
        |> Ash.create!()

      assert {:error, %Ash.Error.Forbidden{}} =
               UnknownPost
               |> Ash.Changeset.for_create(:create, %{
                 text: "nope",
                 organization_id: org.id
               })
               |> Ash.create(actor: %{id: actor_id})

      assert_received {:custom_check_invoked, 1}
      assert [] = Ash.read!(UnknownPost, authorize?: false)
    end
  end

  describe "policy combining a relationship filter and a :unknown-deferred check" do
    test "authorizes when both the filter matches and check/4 returns the record" do
      actor_id = Ash.UUID.generate()

      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{owner_id: actor_id})
        |> Ash.create!()

      assert {:ok, %MixedPost{}} =
               MixedPost
               |> Ash.Changeset.for_create(:create, %{
                 text: "ok-#{actor_id}",
                 organization_id: org.id
               })
               |> Ash.create(actor: %{id: actor_id})

      assert_received {:custom_check_invoked, 1}
    end

    test "forbids when the filter matches but check/4 rejects the record" do
      actor_id = Ash.UUID.generate()

      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{owner_id: actor_id})
        |> Ash.create!()

      assert {:error, %Ash.Error.Forbidden{}} =
               MixedPost
               |> Ash.Changeset.for_create(:create, %{
                 text: "wrong-text",
                 organization_id: org.id
               })
               |> Ash.create(actor: %{id: actor_id})

      assert [] = Ash.read!(MixedPost, authorize?: false)
    end

    test "forbids when check/4 accepts but the filter rejects the record" do
      actor_id = Ash.UUID.generate()
      other_owner_id = Ash.UUID.generate()

      org =
        Organization
        |> Ash.Changeset.for_create(:create, %{owner_id: other_owner_id})
        |> Ash.create!()

      assert {:error, %Ash.Error.Forbidden{}} =
               MixedPost
               |> Ash.Changeset.for_create(:create, %{
                 text: "ok-#{actor_id}",
                 organization_id: org.id
               })
               |> Ash.create(actor: %{id: actor_id})

      assert [] = Ash.read!(MixedPost, authorize?: false)
    end
  end
end
