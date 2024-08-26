defmodule AshPostgres.RelWithParentFilterTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Author

  require Ash.Query

  test "filter on relationship using parent works as expected when used in aggregate" do
    %{id: author_id} =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "John"})
    |> Ash.create!()

    # here we get the expected result of 1 because it is done in the same query
    assert %{num_of_authors_with_same_first_name: 1} =
             Author
             |> Ash.Query.for_read(:read)
             |> Ash.Query.filter(id == ^author_id)
             |> Ash.Query.load(:num_of_authors_with_same_first_name)
             |> Ash.read_one!()
  end

  test "filter constructed from input on relationship using parent works as expected" do
    %{id: author_id} =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    %{id: author2_id} =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John"})
      |> Ash.create!()

    filter =
      Ash.Filter.parse_input!(Author, %{
        "authors_with_same_first_name" => %{
          "id" => %{
            "eq" => author_id
          }
        }
      })

    # here we get the expected result of 1 because it is done in the same query
    assert %{id: ^author2_id} =
             Author
             |> Ash.Query.for_read(:read)
             |> Ash.Query.do_filter(filter)
             |> Ash.read_one!(authorize?: true)
  end

  test "filter on relationship using parent works as expected when loading relationship" do
    %{id: author_id} =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "John"})
    |> Ash.create!()

    assert %{authors_with_same_first_name: authors} =
             Author
             |> Ash.Query.for_read(:read)
             |> Ash.Query.filter(id == ^author_id)
             # right now it first loads the contact
             # then it loads the relationship
             # but when doing that it does a inner lateral join
             # instead of using the id from the parent relationship
             |> Ash.Query.load(:authors_with_same_first_name)
             |> Ash.read_one!()

    assert length(authors) == 1
  end
end
