# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.PostgresInTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Post

  require Ash.Query

  describe "postgres_in/2" do
    test "generates SQL IN (...) syntax instead of = ANY(...)" do
      {query, _vars} =
        Post
        |> Ash.Query.filter(postgres_in(id, [^Ash.UUID.generate(), ^Ash.UUID.generate()]))
        |> Ash.data_layer_query!()
        |> Map.get(:query)
        |> then(&AshPostgres.TestRepo.to_sql(:all, &1))

      assert query =~ " IN ("
      refute query =~ "ANY("
    end

    test "returns matching records" do
      post1 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "first"})
        |> Ash.create!()

      post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "second"})
        |> Ash.create!()

      _post3 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "third"})
        |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(postgres_in(id, [^post1.id, ^post2.id]))
        |> Ash.read!()
        |> Enum.sort_by(& &1.title)

      assert length(results) == 2
      assert [%{title: "first"}, %{title: "second"}] = results
    end

    test "returns empty list when no values match" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "existing"})
      |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(postgres_in(id, [^Ash.UUID.generate()]))
        |> Ash.read!()

      assert results == []
    end

    test "works with a single value" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "only"})
        |> Ash.create!()

      results =
        Post
        |> Ash.Query.filter(postgres_in(id, [^post.id]))
        |> Ash.read!()

      assert length(results) == 1
      assert [%{title: "only"}] = results
    end
  end
end
