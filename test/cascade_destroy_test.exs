# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgresTest.CascadeDestroyTest do
  use AshPostgres.RepoCase, async: true

  alias AshPostgres.Test.{Post, Rating}

  test "can cascade destroy a has_many with parent filter" do
    post =
      Post.create!("post", %{score: 1})

    Rating
    |> Ash.Changeset.for_create(:create, %{score: 2, resource_id: post.id})
    |> Ash.Changeset.set_context(%{data_layer: %{table: "post_ratings"}})
    |> Ash.create!()

    post
    |> Ash.Changeset.for_destroy(:cascade_destroy)
    |> Ash.destroy!()

    assert [] =
             Rating
             |> Ash.Query.for_read(:read)
             |> Ash.Query.set_context(%{data_layer: %{table: "post_ratings"}})
             |> Ash.read!()
  end
end
