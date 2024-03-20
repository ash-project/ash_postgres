defmodule AshPostgres.ManualUpdateTest do
  use AshPostgres.RepoCase, async: true

  test "Manual update defined in a module to update an attribute" do
    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.create!()

    AshPostgres.Test.Comment
    |> Ash.Changeset.new(%{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    post =
      post
      |> Ash.Changeset.for_update(:manual_update)
      |> Ash.update!()

    assert post.title == "manual"

    # The manual update has a call to Ash.Changeset.load that should
    # cause the comments to be loaded
    assert Ash.Resource.loaded?(post, :comments)
    assert Enum.count(post.comments) == 1
  end
end
