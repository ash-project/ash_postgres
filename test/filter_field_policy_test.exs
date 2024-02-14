defmodule FilterFieldPolicyTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Api, Post, Organization}

  require Ash.Query

  setup do
    # I needed this to make the query actually fail
    # this triggers an exeption in the reporting of
    # the policy breakdowns because the policies are
    # nil

    # Without this it would just run the query which
    # might be even worse as the policies are not applied
    # correctly and I guess `nil` is a special case for
    # field policies because you can have no polcies
    # and that is still valid?
    current_level = Logger.level()
    current_setting = Application.get_env(:ash, :policies)

    Application.put_env(
      :ash,
      :policies,
      Keyword.merge(current_setting |> List.wrap(), log_policy_breakdowns: current_level)
    )

    on_exit(fn ->
      Application.put_env(:ash, :policies, current_setting)
    end)
  end

  test "filter uses the correct field policies when exanding refs" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "test_org"})
      |> Api.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id})
    |> Api.create!()

    filter = Ash.Filter.parse_input!(Post, %{organization: %{name: %{ilike: "%org"}}})

    assert [_] =
             Post
             |> Ash.Query.do_filter(filter)
             |> Ash.Query.for_read(:allow_any)
             |> Api.read!(actor: %{id: "%test"})
  end
end
