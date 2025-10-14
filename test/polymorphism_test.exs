# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.PolymorphismTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Post, Rating}

  require Ash.Query

  test "you can create related data" do
    Post
    |> Ash.Changeset.for_create(:create, rating: %{score: 10})
    |> Ash.create!()

    assert [%{score: 10}] =
             Rating
             |> Ash.Query.set_context(%{data_layer: %{table: "post_ratings"}})
             |> Ash.read!()
  end

  test "you can read related data" do
    Post
    |> Ash.Changeset.for_create(:create, rating: %{score: 10})
    |> Ash.create!()

    assert [%{score: 10}] =
             Post
             |> Ash.Query.load(:ratings)
             |> Ash.read_one!()
             |> Map.get(:ratings)
  end
end
