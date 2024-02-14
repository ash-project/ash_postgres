defmodule FilterFieldPolicyTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Api, Post, Organization, User}

  require Ash.Query

  test "filter uses the correct field policies when exanding refs" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "test_org"})
      |> Api.create!()

    User
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, name: "foo bar"})
    |> Api.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id})
    |> Api.create!()

    filter = Ash.Filter.parse_input!(Post, %{organization: %{name: %{ilike: "%org"}}})

    assert [_] =
             Post
             |> Ash.Query.do_filter(filter)
             |> Ash.Query.for_read(:allow_any)
             |> Api.read!(actor: %{id: "test"})

    filter = Ash.Filter.parse_input!(Post, %{organization: %{users: %{name: %{ilike: "%bar"}}}})

    assert [_] =
             Post
             |> Ash.Query.do_filter(filter)
             |> Ash.Query.for_read(:allow_any)
             |> Api.read!(actor: %{id: "test"})
  end
end
