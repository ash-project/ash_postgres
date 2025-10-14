# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ParentSortTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Organization, Post, User}

  require Ash.Query

  test "can reference parent field when declaring default sort in has_many no_attributes? relationship" do
    organization =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "test_org"})
      |> Ash.create!()

    User
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, name: "foo bar"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{organization_id: organization.id, title: "test_org"})
    |> Ash.create!()

    # just asserting it doesn't errror
    Post
    |> Ash.Query.load(:recommendations)
    |> Ash.read!(authorize?: false)
  end
end
