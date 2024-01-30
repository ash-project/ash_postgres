defmodule AshPostgres.ManualUpdateTest do
  use AshPostgres.RepoCase, async: true

  test "Manual update defined in a module to update an attribute" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.new(%{title: "match"})
      |> AshPostgres.Test.Api.create!()

    post =
      post
      |> Ash.Changeset.for_update(:manual_update)
      |> AshPostgres.Test.Api.update!()

    assert post.title == "manual"
  end
end
