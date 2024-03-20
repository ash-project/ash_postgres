defmodule AshPostgres.EmbeddableResourceTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Author, Bio, Post

  require Ash.Query

  setup do
    post =
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Ash.create!()

    %{post: post}
  end

  test "calculations can load json", %{post: post} do
    assert %{calc_returning_json: %AshPostgres.Test.Money{amount: 100, currency: :usd}} =
             Ash.load!(post, :calc_returning_json)
  end

  test "embeds with list attributes set to nil are loaded as nil" do
    post =
      Author
      |> Ash.Changeset.new(%{bio: %Bio{list_of_strings: nil}})
      |> Ash.create!()

    assert is_nil(post.bio.list_of_strings)

    post = Ash.reload!(post)

    assert is_nil(post.bio.list_of_strings)
  end
end
