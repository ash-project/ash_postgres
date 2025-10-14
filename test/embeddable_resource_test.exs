# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.EmbeddableResourceTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Author, Bio, Post}

  require Ash.Query

  setup do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    %{post: post}
  end

  test "calculations can load json", %{post: post} do
    assert %{calc_returning_json: %AshPostgres.Test.Money{amount: 100, currency: :usd}} =
             Ash.load!(post, :calc_returning_json)
  end

  test "embeds with list attributes set to nil are loaded as nil" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{bio: %Bio{list_of_strings: nil}})
      |> Ash.create!()

    assert is_nil(author.bio.list_of_strings)

    author = Ash.reload!(author)

    assert is_nil(author.bio.list_of_strings)
  end
end
