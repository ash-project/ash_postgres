# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.PolymorphismTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Label, Post, Rating}

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

  test "can update related data" do
    %{id: post_id} = post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    label =
      Label
      |> Ash.Changeset.for_create(:create, %{value: "a_label"})
      |> Ash.create!()

    label_1 =
      Label
      |> Ash.Changeset.for_create(:create, %{value: "another_label"})
      |> Ash.create!()

    assert %{id: ^post_id} = post
      |> Ash.Changeset.for_update(:set_labels, labels: [label])
      |> Ash.update!()

    assert %{id: ^post_id} = post
      |> Ash.Changeset.for_update(:set_labels, labels: [label_1])
      |> Ash.update!()
  end
end
