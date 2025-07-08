defmodule AshPostgres.CombinationTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

  alias AshPostgres.Test.Author
  alias AshPostgres.Test.Post

  describe "combinations in actions" do
    test "with no data" do
      Post
      |> Ash.Query.for_read(:first_and_last_post)
      |> Ash.read!()
    end

    test "with data" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title3"})
      |> Ash.create!()

      assert [%{title: "title1"}, %{title: "title3"}] =
               Post
               |> Ash.Query.for_read(:first_and_last_post)
               |> Ash.read!()
    end

    test "with data and sort" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title3"})
      |> Ash.create!()

      assert [%{title: "title3"}, %{title: "title1"}] =
               Post
               |> Ash.Query.for_read(:first_and_last_post)
               |> Ash.Query.sort(title: :desc)
               |> Ash.read!()
    end

    test "with data and sort, limit and filter" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title3"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title4"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title5"})
      |> Ash.create!()

      assert ["title5", "title4", "title1"] =
               Post
               |> Ash.Query.for_read(:first_and_last_two_posts)
               |> Ash.Query.sort(title: :desc)
               |> Ash.Query.filter(title in ["title4", "title5", "title1"])
               |> Ash.Query.limit(3)
               |> Ash.read!()
               |> Enum.map(& &1.title)

      assert ["title5", "title4", "title2"] =
               Post
               |> Ash.Query.for_read(:first_and_last_two_posts)
               |> Ash.Query.sort(title: :desc)
               |> Ash.Query.filter(title in ["title4", "title5", "title2"])
               |> Ash.Query.limit(3)
               |> Ash.read!()
               |> Enum.map(& &1.title)
    end
  end

  describe "combinations" do
    test "it combines multiple queries into one result set" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post3"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post4"})
      |> Ash.create!()

      assert [%{title: "post4"}, %{title: "post1"}] =
               Post
               |> Ash.Query.combination_of([
                 Ash.Query.Combination.base(
                   filter: expr(title == "post4"),
                   limit: 1
                 ),
                 Ash.Query.Combination.union_all(
                   filter: expr(title == "post1"),
                   limit: 1
                 )
               ])
               |> Ash.Query.sort(title: :desc)
               |> Ash.read!()
               |> Enum.map(&Map.take(&1, [:title]))
    end

    test "you can define computed properties" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post3"})
      |> Ash.create!()

      assert [%Post{title: "post3", calculations: %{post_group: 1}}] =
               Post
               |> Ash.Query.combination_of([
                 Ash.Query.Combination.base(
                   filter: expr(title == "post3"),
                   select: [:id],
                   limit: 1,
                   calculations: %{
                     post_group: calc(1, type: :integer),
                     common_value: calc(1, type: :integer)
                   }
                 ),
                 Ash.Query.Combination.union_all(
                   filter: expr(title == "post1"),
                   select: [:id],
                   calculations: %{
                     post_group: calc(2, type: :integer),
                     common_value: calc(1, type: :integer)
                   },
                   limit: 1
                 )
               ])
               |> Ash.Query.sort([{calc(^combinations(:post_group)), :asc}])
               |> Ash.Query.distinct([calc(^combinations(:common_value))])
               |> Ash.Query.calculate(:post_group, :integer, expr(^combinations(:post_group)))
               |> Ash.read!()
    end

    test "it handles combinations with intersect" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "shared"})
      |> Ash.create!()

      assert [%Post{title: "shared"}] =
               Post
               |> Ash.Query.combination_of([
                 Ash.Query.Combination.base(filter: expr(title in ["post1", "shared"])),
                 Ash.Query.Combination.intersect(filter: expr(title in ["post2", "shared"]))
               ])
               |> Ash.read!()
    end

    test "it handles combinations with except" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "shared"})
      |> Ash.create!()

      result =
        Post
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(title in ["post1", "shared"])),
          Ash.Query.Combination.except(filter: expr(title == "shared"))
        ])
        |> Ash.read!()

      assert length(result) == 1
      assert hd(result).title == "post1"
    end

    test "combinations with multiple union_all" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post3"})
      |> Ash.create!()

      result =
        Post
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(filter: expr(title == "post1")),
          Ash.Query.Combination.union_all(filter: expr(title == "post2")),
          Ash.Query.Combination.union_all(filter: expr(title == "post3"))
        ])
        |> Ash.read!()

      assert length(result) == 3
      assert Enum.any?(result, &(&1.title == "post1"))
      assert Enum.any?(result, &(&1.title == "post2"))
      assert Enum.any?(result, &(&1.title == "post3"))
    end

    test "combination with offset" do
      # Create posts with increasing title numbers for predictable sort order
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post3"})
      |> Ash.create!()

      result =
        Post
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(
            filter: expr(contains(title, "post")),
            offset: 1,
            limit: 2,
            sort: [title: :asc]
          )
        ])
        |> Ash.read!()

      assert length(result) == 2
      assert hd(result).title == "post2"
      assert List.last(result).title == "post3"
    end

    test "combinations with complex calculations" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      result =
        Post
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(
            filter: expr(title == "post1"),
            calculations: %{
              prefix: calc("first", type: :string),
              full_title: calc("first-" <> title, type: :string)
            }
          ),
          Ash.Query.Combination.union_all(
            filter: expr(title == "post2"),
            calculations: %{
              prefix: calc("second", type: :string),
              full_title: calc("second-" <> title, type: :string)
            }
          )
        ])
        |> Ash.Query.calculate(:title_prefix, :string, expr(^combinations(:prefix)))
        |> Ash.Query.calculate(:display_title, :string, expr(^combinations(:full_title)))
        |> Ash.read!()

      post1 = Enum.find(result, &(&1.title == "post1"))
      post2 = Enum.find(result, &(&1.title == "post2"))

      assert post1.calculations.title_prefix == "first"
      assert post1.calculations.display_title == "first-post1"
      assert post2.calculations.title_prefix == "second"
      assert post2.calculations.display_title == "second-post2"
    end

    test "combinations with sorting by calculation" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post3"})
      |> Ash.create!()

      result =
        Post
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(calculations: %{sort_order: calc(3, type: :integer)}),
          Ash.Query.Combination.union_all(
            filter: expr(title == "post2"),
            calculations: %{sort_order: calc(1, type: :integer)}
          ),
          Ash.Query.Combination.union_all(
            filter: expr(title == "post3"),
            calculations: %{sort_order: calc(2, type: :integer)}
          )
        ])
        |> Ash.Query.sort([{calc(^combinations(:sort_order)), :asc}, {:title, :asc}])
        |> Ash.Query.distinct(:title)
        |> Ash.read!()

      assert [first, second, third | _] = result
      assert first.title == "post2"
      assert second.title == "post3"
      assert third.title == "post1"
    end

    test "combination with distinct" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1", score: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2", score: 10})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post3", score: 20})
      |> Ash.create!()

      result =
        Post
        |> Ash.Query.combination_of([
          Ash.Query.Combination.base(
            filter: expr(score == 10),
            select: [:id, :score],
            calculations: %{score_group: calc("low", type: :string)}
          ),
          Ash.Query.Combination.union_all(
            filter: expr(score == 20),
            select: [:id, :score],
            calculations: %{score_group: calc("high", type: :string)}
          )
        ])
        |> Ash.Query.distinct([{calc(^combinations(:score_group)), :asc}])
        |> Ash.Query.calculate(:upper_title, :string, expr(fragment("UPPER(?)", title)))
        |> Ash.read!()

      assert Enum.all?(result, &(&1.calculations.upper_title == String.upcase(&1.title)))

      # Should only have 2 results since we're distinct on score group
      assert length(result) == 2

      groups =
        Enum.map(result, & &1.calculations[:score_group])

      assert "low" in groups
      assert "high" in groups
    end

    test "combination with filters not included in the field set" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "post1", score: 10, category: "category1"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post2", score: 10, category: "category2"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "post3", score: 20, category: "category3"})
      |> Ash.create!()

      assert ["category1"] =
               Post
               |> Ash.Query.combination_of([
                 Ash.Query.Combination.base(
                   filter: expr(score == 10),
                   select: [:id, :score],
                   calculations: %{score_group: calc("low", type: :string)}
                 ),
                 Ash.Query.Combination.union_all(
                   filter: expr(score == 20),
                   select: [:id, :score],
                   calculations: %{score_group: calc("high", type: :string)}
                 )
               ])
               |> Ash.Query.filter(category == "category1")
               |> Ash.Query.distinct([{calc(^combinations(:score_group)), :asc}])
               |> Ash.Query.calculate(:upper_title, :string, expr(fragment("UPPER(?)", title)))
               |> Ash.read!()
               |> Enum.map(&to_string(&1.category))
    end
  end

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
