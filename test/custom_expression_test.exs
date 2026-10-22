# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CustomExpressionTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{Author, Post}

  require Ash.Query
  require Ash.Sort
  import Ash.Expr

  test "unique constraint errors are properly caught" do
    Ash.create!(AshPostgres.Test.Profile, %{description: "foo"})

    assert [_] =
             AshPostgres.Test.Profile
             |> Ash.Query.for_read(:by_indirectly_matching_description, %{term: "fop"})
             |> Ash.read!()

    assert [_] =
             AshPostgres.Test.Profile
             |> Ash.Query.for_read(:by_directly_matching_description, %{term: "fop"})
             |> Ash.read!()
  end

  test "relationship references in custom expression arguments are joined" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "fred"})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "no match"})
    |> Ash.create!()

    assert [%{title: "match"}] =
             Post
             |> Ash.Query.filter(trigram_word_similarity(author.first_name, "fred") > 0.9)
             |> Ash.read!()

    assert [%{title: "match"}] =
             Post
             |> Ash.Query.filter(trigram_word_similarity(author_first_name_calc, "fred") > 0.9)
             |> Ash.read!()

    assert [%{title: "match", calculations: %{similarity: similarity}}] =
             Post
             |> Ash.Query.filter(title == "match")
             |> Ash.Query.calculate(
               :similarity,
               :float,
               expr(trigram_word_similarity(author.first_name, "fred"))
             )
             |> Ash.read!()

    assert similarity > 0.9

    assert [%{title: "match"}, %{title: "no match"}] =
             Post
             |> Ash.Query.sort([
               {Ash.Sort.expr_sort(trigram_word_similarity(author.first_name, "fred"), :float),
                :desc_nils_last}
             ])
             |> Ash.read!()
  end
end
