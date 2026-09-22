# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.EncodeErrorTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query

  # One past the `bigint` range. `Ash.Type.Integer` accepts it; Postgrex cannot encode it.
  @too_big 9_223_372_036_854_775_808

  test "an integer past the bigint range in a filter is an invalid filter value" do
    assert {:error, %Ash.Error.Invalid{errors: [error]}} =
             Post
             |> Ash.Query.filter(score == ^@too_big)
             |> Ash.read()

    assert %Ash.Error.Query.InvalidFilterValue{message: message} = error
    refute message =~ "Postgrex"
  end

  test "an update with an integer past the bigint range is an invalid change" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title", score: 1})
      |> Ash.create!()

    assert {:error, %Ash.Error.Invalid{errors: [error]}} =
             post
             |> Ash.Changeset.for_update(:update, %{score: @too_big})
             |> Ash.update()

    assert %Ash.Error.Changes.InvalidChanges{} = error
  end

  test "a create with an integer past the bigint range is an invalid change" do
    assert {:error, %Ash.Error.Invalid{errors: [error]}} =
             Post
             |> Ash.Changeset.for_create(:create, %{title: "title", score: @too_big})
             |> Ash.create()

    assert %Ash.Error.Changes.InvalidChanges{message: message} = error
    refute message =~ "Postgrex"
  end

  test "an in-range integer still filters and stores" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title", score: 9_223_372_036_854_775_807})
    |> Ash.create!()

    assert [%Post{}] =
             Post
             |> Ash.Query.filter(score == ^9_223_372_036_854_775_807)
             |> Ash.read!()
  end
end
