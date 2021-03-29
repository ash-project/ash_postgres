defmodule AshPostgres.PolymorphismTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post, Rating}

  require Ash.Query

  test "you can create related data" do
    Post
    |> Ash.Changeset.for_create(:create, rating: %{score: 10})
    |> Api.create!(stacktraces?: true)

    assert [%{score: 10}] =
             Rating
             |> Ash.Query.set_context(%{data_layer: %{table: "post_ratings"}})
             |> Api.read!(stacktraces?: true)
  end

  test "you can read related data" do
    Post
    |> Ash.Changeset.for_create(:create, rating: %{score: 10})
    |> Api.create!(stacktraces?: true)

    assert [%{score: 10}] =
             Post
             |> Ash.Query.load(:ratings)
             |> Api.read_one!()
             |> Map.get(:ratings)
  end
end
