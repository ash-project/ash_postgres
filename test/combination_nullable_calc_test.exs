defmodule AshPostgres.CombinationNullableCalcTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Author
  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  describe "combination_of with nullable calculations" do
    test "combination query with allow_nil? calculation loses ORDER BY" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Zebra", score: 5})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Apple", score: 25})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Dog", score: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Cat", score: 20})
      |> Ash.create!()

      query =
        Post
        |> Ash.Query.sort([{:title, :asc}])
        |> Ash.Query.load([:latest_comment_title])
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(
            filter: expr(score < 15),
            calculations: %{
              sort_order: calc(score * 20, type: :integer)
            },
            sort: [{calc(score * 20, type: :integer), :desc}]
          ),
          Ash.Query.Combination.union(
            filter: expr(score >= 15),
            calculations: %{
              sort_order: calc(score * 5, type: :integer)
            },
            sort: [{calc(score * 5, type: :integer), :desc}]
          )
        ])
        |> Ash.Query.sort([{calc(^combinations(:sort_order)), :desc}], prepend?: true)

      result = Ash.read!(query)
      titles = Enum.map(result, & &1.title)
      # Expected order: sort_order DESC, then title ASC
      # Dog(200), Apple(125), Cat(100), Zebra(100)
      expected_title_order = ["Dog", "Apple", "Cat", "Zebra"]
      assert titles == expected_title_order
    end

    test "combination query without nullable calc works" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Zebra", score: 5})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Apple", score: 25})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Dog", score: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "Cat", score: 20})
      |> Ash.create!()

      query =
        Post
        |> Ash.Query.sort([{:title, :asc}])
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(
            filter: expr(score < 15),
            calculations: %{
              sort_order: calc(score * 20, type: :integer)
            },
            sort: [{calc(score * 20, type: :integer), :desc}]
          ),
          Ash.Query.Combination.union(
            filter: expr(score >= 15),
            calculations: %{
              sort_order: calc(score * 5, type: :integer)
            },
            sort: [{calc(score * 5, type: :integer), :desc}]
          )
        ])
        |> Ash.Query.sort([{calc(^combinations(:sort_order)), :desc}], prepend?: true)

      result = Ash.read!(query)
      titles = Enum.map(result, & &1.title)
      # Expected order: sort_order DESC, then title ASC
      # Dog(200), Apple(125), Cat(100), Zebra(100)
      expected_title_order = ["Dog", "Apple", "Cat", "Zebra"]
      assert titles == expected_title_order
    end
  end

  describe "Author combination_of with nullable calculations" do
    test "Author combination query with allow_nil? calculation loses ORDER BY" do
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Zebra", last_name: "User"})
      |> Ash.create!()

      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Apple", last_name: "User"})
      |> Ash.create!()

      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Dog", last_name: "User"})
      |> Ash.create!()

      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Cat", last_name: "User"})
      |> Ash.create!()

      query =
        Author
        |> Ash.Query.sort([{:first_name, :asc}])
        |> Ash.Query.load([:profile_description_calc])
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(
            filter: expr(first_name in ["Zebra", "Dog"]),
            calculations: %{
              sort_order: calc(1000, type: :integer)
            },
            sort: [{calc(1000, type: :integer), :desc}]
          ),
          Ash.Query.Combination.union(
            filter: expr(first_name in ["Apple", "Cat"]),
            calculations: %{
              sort_order: calc(500, type: :integer)
            },
            sort: [{calc(500, type: :integer), :desc}]
          )
        ])
        |> Ash.Query.sort([{calc(^combinations(:sort_order)), :desc}], prepend?: true)

      result = Ash.read!(query)
      first_names = Enum.map(result, & &1.first_name)
      # Expected order: sort_order DESC, then first_name ASC
      # [Dog, Zebra] (1000), [Apple, Cat] (500) → Dog, Zebra, Apple, Cat
      expected_name_order = ["Dog", "Zebra", "Apple", "Cat"]
      assert first_names == expected_name_order
    end

    test "Author combination query without nullable calc works" do
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Zebra", last_name: "User"})
      |> Ash.create!()

      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Apple", last_name: "User"})
      |> Ash.create!()

      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Dog", last_name: "User"})
      |> Ash.create!()

      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Cat", last_name: "User"})
      |> Ash.create!()

      query =
        Author
        |> Ash.Query.sort([{:first_name, :asc}])
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(
            filter: expr(first_name in ["Zebra", "Dog"]),
            calculations: %{
              sort_order: calc(1000, type: :integer)
            }
          ),
          Ash.Query.Combination.union(
            filter: expr(first_name in ["Apple", "Cat"]),
            calculations: %{
              sort_order: calc(500, type: :integer)
            }
          )
        ])
        |> Ash.Query.sort([{calc(^combinations(:sort_order)), :desc}], prepend?: true)

      result = Ash.read!(query)
      first_names = Enum.map(result, & &1.first_name)
      # Expected order: sort_order DESC, then first_name ASC
      # [Dog, Zebra] (1000), [Apple, Cat] (500) → Dog, Zebra, Apple, Cat
      expected_name_order = ["Dog", "Zebra", "Apple", "Cat"]
      assert first_names == expected_name_order
    end
  end
end
