# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
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

  test "can filter on a doubly-nested embedded resource field" do
    Author
    |> Ash.Changeset.for_create(:create, %{
      bio: %{address: %{city: "Sydney", country: "AU"}}
    })
    |> Ash.create!()

    Author
    |> Ash.Changeset.for_create(:create, %{
      bio: %{address: %{city: "Melbourne", country: "AU"}}
    })
    |> Ash.create!()

    results =
      Author
      |> Ash.Query.filter(bio[:address][:city] == "Sydney")
      |> Ash.read!()

    assert length(results) == 1
    assert hd(results).bio.address.city == "Sydney"
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
