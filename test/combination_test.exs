defmodule AshPostgres.CombinationTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.Post

  require Ash.Query
  import Ash.Expr

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
end
