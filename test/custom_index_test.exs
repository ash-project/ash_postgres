# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CustomIndexTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query

  test "unique constraint errors are properly caught" do
    Post
    |> Ash.Changeset.for_create(:create, %{
      title: "first",
      uniq_custom_one: "what",
      uniq_custom_two: "what2"
    })
    |> Ash.create!()

    assert_raise Ash.Error.Invalid,
                 ~r/Invalid value provided for uniq_custom_one: dude what the heck/,
                 fn ->
                   Post
                   |> Ash.Changeset.for_create(:create, %{
                     title: "first",
                     uniq_custom_one: "what",
                     uniq_custom_two: "what2"
                   })
                   |> Ash.create!()
                 end
  end

  test "directed custom index fields populate error_fields" do
    {:ok, index} =
      AshPostgres.CustomIndex.transform(%AshPostgres.CustomIndex{
        fields: [:tenant_id, {:desc, :occurred_at}],
        unique: true,
        name: "events_tenant_id_occurred_at_index"
      })

    assert index.error_fields == [:tenant_id, :occurred_at]
  end
end
