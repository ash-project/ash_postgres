defmodule AshPostgres.EmbeddableResourceTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Api, Post}

  require Ash.Query

  setup do
    post =
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

    %{post: post}
  end

  test "calculations can load json", %{post: post} do
    assert %{calc_returning_json: %AshPostgres.Test.Money{amount: 100, currency: :usd}} =
             Api.load!(post, :calc_returning_json)
  end
end
