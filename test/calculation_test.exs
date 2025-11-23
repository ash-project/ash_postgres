# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.CalculationTest do
  alias AshPostgres.Test.RecordTempEntity
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{
    Account,
    Author,
    Comedian,
    Comment,
    Post,
    PostTag,
    Record,
    Tag,
    TempEntity,
    User
  }

  require Ash.Query
  import Ash.Expr
  import ExUnit.CaptureLog

  setup do
    on_exit(fn ->
      Logger.configure(level: :warning)
    end)
  end

  test "a calculation that references a first optimizable aggregate can be sorted on" do
    author1 =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "abc"
      })
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", author_id: author1.id})
      |> Ash.create!()

    author2 =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "def"
      })
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", author_id: author2.id})
      |> Ash.create!()

    post1_id = post.id
    post2_id = post2.id

    assert [%{id: ^post2_id}, %{id: ^post1_id}] =
             Post
             |> Ash.Query.sort(author_first_name_ref_agg_calc: :desc)
             |> Ash.read!()

    assert [%{id: ^post1_id}, %{id: ^post2_id}] =
             Post
             |> Ash.Query.sort(author_first_name_ref_agg_calc: :asc)
             |> Ash.read!()
  end

  test "start_of_day functions the same as Elixir's start of day" do
    assert Ash.calculate!(Post, :start_of_day, data_layer?: true) ==
             Ash.Expr.eval!(Ash.Expr.expr(start_of_day(now(), "EST")))
  end

  @tag :regression
  test "an expression calculation that requires a left join & distinct doesn't raise errors on out of order params" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Post
    |> Ash.Query.load([
      :comment_title,
      :category_label,
      score_plus: %{amount: 10},
      max_comment_similarity: %{to: "foobar"}
    ])
    |> Ash.Query.load_calculation_as(:comment_title, {:some, :example})
    |> Ash.Query.load_calculation_as(:max_comment_similarity, {:some, :other_thing_again}, %{
      to: "foobar"
    })
    |> Ash.Query.load_calculation_as(:category_label, {:some, :other_thing})
    |> Ash.Query.sort(:title)
    |> Ash.read!()
  end

  test "runtime loading calculation with fragment referencing aggregate works correctly" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "test post"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "comment1", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "comment2", likes: 15})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    result =
      Post
      |> Ash.Query.load([:comment_metric, :complex_comment_metric, :multi_agg_calc])
      |> Ash.read!()

    assert [post] = result
    assert is_integer(post.comment_metric)
    assert is_integer(post.complex_comment_metric)
    assert is_integer(post.multi_agg_calc)
  end

  test "expression calculations don't load when `reuse_values?` is true" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    Logger.configure(level: :debug)

    log1 =
      capture_log(fn ->
        post
        |> Ash.load!(:title_twice)
      end)

    refute log1 == ""

    log2 =
      capture_log(fn ->
        post
        |> Ash.load!(:title_twice, reuse_values?: true)

        assert "in calc:" <> _ =
                 post
                 |> Ash.load!(:title_twice_with_calc, reuse_values?: true)
                 |> Map.get(:title_twice_with_calc)
      end)

    assert log2 == ""
  end

  test "calculations use `calculate/3` when possible" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    Logger.configure(level: :debug)

    log =
      capture_log(fn ->
        assert "in calc:" <> _ = Ash.calculate!(post, :title_twice_with_calc, reuse_values?: true)
      end)

    assert log == ""
  end

  test "an expression calculation can be filtered on" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

    post3 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title3"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    post
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post2, post3], type: :append_and_remove)
    |> Ash.update!()

    post2
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post3], type: :append_and_remove)
    |> Ash.update!()

    assert [%{c_times_p: 6, title: "match"}] =
             Post
             |> Ash.Query.load(:c_times_p)
             |> Ash.read!()
             |> Enum.filter(&(&1.c_times_p == 6))

    assert [
             %{c_times_p: %Ash.NotLoaded{}, title: "match"}
           ] =
             Post
             |> Ash.Query.filter(c_times_p == 6)
             |> Ash.read!()

    assert [] =
             Post
             |> Ash.Query.filter(author: [has_posts: true])
             |> Ash.read!()
  end

  test "calculations can refer to to_one path attributes in filters" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "Foo",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert [%{author_first_name_calc: "Foo"}] =
             Post
             |> Ash.Query.filter(author_first_name_calc == "Foo")
             |> Ash.Query.load(:author_first_name_calc)
             |> Ash.read!()
  end

  test "calculations can refer to to_one path attributes in sorts" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "Foo",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert [%{author_first_name_calc: "Foo"}] =
             Post
             |> Ash.Query.sort(:author_first_name_calc)
             |> Ash.Query.load(:author_first_name_calc)
             |> Ash.read!()
  end

  test "calculations evaluate `exists` as expected" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "Foo",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    assert [%{has_author: true, has_comments: true}] =
             Post
             |> Ash.Query.load([:has_author, :has_comments])
             |> Ash.read!()

    # building on top of an exists also works
    author =
      author |> Ash.load!([:has_posts, :has_no_posts])

    assert author.has_posts
    refute author.has_no_posts
  end

  test "calculations can refer to embedded attributes" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{bio: %{title: "Mr.", bio: "Bones"}})
      |> Ash.create!()

    assert %{title: "Mr."} =
             Author
             |> Ash.Query.filter(id == ^author.id)
             |> Ash.Query.load(:title)
             |> Ash.read_one!()
  end

  test "calculations can use the || operator" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{bio: %{title: "Mr.", bio: "Bones"}})
      |> Ash.create!()

    assert %{first_name_or_bob: "bob"} =
             Author
             |> Ash.Query.filter(id == ^author.id)
             |> Ash.Query.load(:first_name_or_bob)
             |> Ash.read_one!()
  end

  test "calculations can use the && operator" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "fred",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Ash.create!()

    assert %{first_name_and_bob: "bob"} =
             Author
             |> Ash.Query.filter(id == ^author.id)
             |> Ash.Query.load(:first_name_and_bob)
             |> Ash.read_one!()
  end

  test "calculations can be used in related filters" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

    post3 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title3"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "no_match"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    post
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post2, post3], type: :append_and_remove)
    |> Ash.update!()

    post2
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post3], type: :append_and_remove)
    |> Ash.update!()

    posts_query =
      Post
      |> Ash.Query.load(:c_times_p)

    assert %{post: %{c_times_p: 6}} =
             Comment
             |> Ash.Query.load(post: posts_query)
             |> Ash.read!()
             |> Enum.filter(&(&1.post.c_times_p == 6))
             |> Enum.at(0)

    query =
      Comment
      |> Ash.Query.filter(post.c_times_p == 6)
      |> Ash.Query.load(post: posts_query)
      |> Ash.Query.limit(1)

    assert [
             %{post: %{c_times_p: 6, title: "match"}}
           ] = Ash.read!(query)

    post |> Ash.load!(:c_times_p)
  end

  test "concat calculation can be filtered on" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "is", last_name: "match"})
      |> Ash.create!()

    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "not", last_name: "match"})
    |> Ash.create!()

    author_id = author.id

    assert %{id: ^author_id} =
             Author
             |> Ash.Query.load(:full_name)
             |> Ash.Query.filter(full_name == "is match")
             |> Ash.read_one!()
  end

  test "concat can be used with a reference" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "is",
        last_name: "match",
        badges: [:foo, :bar]
      })
      |> Ash.create!()

    badges_string =
      Author
      |> Ash.Query.filter(id == ^author.id)
      |> Ash.Query.calculate(:badges_string, :string, expr(string_join(badges)))
      |> Ash.read_one!()
      |> Map.get(:calculations)
      |> Map.get(:badges_string)

    assert badges_string == "foobar"
  end

  test "calculations that refer to aggregates in comparison expressions can be filtered on" do
    Post
    |> Ash.Query.load(:has_future_comment)
    |> Ash.read!()
  end

  test ".calculate works with `exists`" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/Primary key is required for/, fn ->
      refute Ash.calculate!(Post, :author_has_post_with_follower_named_fred)
    end

    refute Ash.calculate!(post, :author_has_post_with_follower_named_fred)
    refute Ash.calculate!(Post, :author_has_post_with_follower_named_fred, refs: %{id: post.id})
  end

  test "calculation works with simple fragments" do
    Post.upper_title!("example")
  end

  test "calculations that refer to aggregates can be authorized" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "comment"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    assert %{has_future_comment: false} =
             Post
             |> Ash.Query.load([:has_future_comment, :latest_comment_created_at])
             |> Ash.Query.for_read(:allow_any, %{})
             |> Ash.read_one!(authorize?: true)

    assert %{has_future_comment: true} =
             Post
             |> Ash.Query.load([:has_future_comment, :latest_comment_created_at])
             |> Ash.Query.for_read(:allow_any, %{})
             |> Ash.read_one!(authorize?: false)

    assert %{has_future_comment: false} =
             Post
             |> Ash.Query.for_read(:allow_any, %{})
             |> Ash.read_one!()
             |> Ash.load!([:has_future_comment, :latest_comment_created_at], authorize?: true)

    assert %{has_future_comment: true} =
             Post
             |> Ash.Query.for_read(:allow_any, %{})
             |> Ash.read_one!()
             |> Ash.load!([:has_future_comment, :latest_comment_created_at], authorize?: false)
  end

  test "conditional calculations can be filtered on" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "tom"})
      |> Ash.create!()

    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "tom", last_name: "holland"})
    |> Ash.create!()

    author_id = author.id

    assert %{id: ^author_id} =
             Author
             |> Ash.Query.load([:conditional_full_name, :full_name])
             |> Ash.Query.filter(conditional_full_name == "(none)")
             |> Ash.read_one!()
  end

  test "parameterized calculations can be filtered on" do
    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "tom", last_name: "holland"})
    |> Ash.create!()

    assert %{param_full_name: "tom holland"} =
             Author
             |> Ash.Query.load(:param_full_name)
             |> Ash.read_one!()

    assert %{param_full_name: "tom~holland"} =
             Author
             |> Ash.Query.load(param_full_name: [separator: "~"])
             |> Ash.read_one!()

    assert %{} =
             Author
             |> Ash.Query.filter(param_full_name(separator: "~") == "tom~holland")
             |> Ash.read_one!()
  end

  test "parameterized related calculations can be filtered on" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "tom", last_name: "holland"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Ash.create!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(author.param_full_name(separator: "~") == "tom~holland")
             |> Ash.read_one!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(
               author.param_full_name(separator: "~") == "tom~holland" and
                 author.param_full_name(separator: " ") == "tom holland"
             )
             |> Ash.read_one!()
  end

  test "parameterized calculations can be sorted on" do
    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "tom", last_name: "holland"})
    |> Ash.create!()

    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "abc", last_name: "def"})
    |> Ash.create!()

    assert [%{first_name: "abc"}, %{first_name: "tom"}] =
             Author
             |> Ash.Query.sort(param_full_name: %{separator: "~"})
             |> Ash.read!()
  end

  test "calculations using if and literal boolean results can run" do
    Post
    |> Ash.Query.load(:was_created_in_the_last_month)
    |> Ash.Query.filter(was_created_in_the_last_month == true)
    |> Ash.read!()
  end

  test "nested conditional calculations can be loaded" do
    Author
    |> Ash.Changeset.for_create(:create, %{last_name: "holland"})
    |> Ash.create!()

    Author
    |> Ash.Changeset.for_create(:create, %{first_name: "tom"})
    |> Ash.create!()

    assert [%{nested_conditional: "No First Name"}, %{nested_conditional: "No Last Name"}] =
             Author
             |> Ash.Query.load(:nested_conditional)
             |> Ash.Query.sort(:nested_conditional)
             |> Ash.read!()
  end

  test "calculations load nullable timestamp aggregates compared to a fragment" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 0})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "aaa", score: 1})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "bbb", score: 0})
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "aaa",
      likes: 1,
      arbitrary_timestamp: DateTime.now!("Etc/UTC")
    })
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "bbb", likes: 1})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "aaa", likes: 2})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Post
    |> Ash.Query.load([:has_future_arbitrary_timestamp])
    |> Ash.read!()
  end

  test "loading a calculation loads its dependent loads" do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{is_active: true})
      |> Ash.create!()

    account =
      Account
      |> Ash.Changeset.for_create(:create, %{is_active: true})
      |> Ash.Changeset.manage_relationship(:user, user, type: :append_and_remove)
      |> Ash.create!()
      |> Ash.load!([:active])

    assert account.active
  end

  describe "string join expression" do
    test "no nil values" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{
          first_name: "Bill",
          last_name: "Jones",
          bio: %{title: "Mr.", bio: "Bones"}
        })
        |> Ash.create!()

      assert %{
               full_name_with_nils: "Bill Jones",
               full_name_with_nils_no_joiner: "BillJones"
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load(:full_name_with_nils)
               |> Ash.Query.load(:full_name_with_nils_no_joiner)
               |> Ash.read_one!()
    end

    test "with nil value" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{
          first_name: "Bill",
          bio: %{title: "Mr.", bio: "Bones"}
        })
        |> Ash.create!()

      assert %{
               full_name_with_nils: "Bill",
               full_name_with_nils_no_joiner: "Bill"
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load(:full_name_with_nils)
               |> Ash.Query.load(:full_name_with_nils_no_joiner)
               |> Ash.read_one!()
    end
  end

  test "arguments with cast_in_query?: false are not cast" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "match", score: 42})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "not", score: 42})
    |> Ash.create!()

    assert [post] =
             Post
             |> Ash.Query.filter(similarity(search: expr(query(search: "match"))))
             |> Ash.read!()

    assert post.title == "match"
  end

  describe "string split expression" do
    test "with the default delimiter" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{
          first_name: "Bill",
          last_name: "Jones",
          bio: %{title: "Mr.", bio: "Bones"}
        })
        |> Ash.create!()

      assert %{
               split_full_name: ["Bill", "Jones"]
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load(:split_full_name)
               |> Ash.read_one!()
    end

    test "trimming whitespace" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{
          first_name: "Bill ",
          last_name: "Jones ",
          bio: %{title: "Mr.", bio: "Bones"}
        })
        |> Ash.create!()

      assert %{
               split_full_name_trim: ["Bill", "Jones"],
               split_full_name: ["Bill", "Jones"]
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load([:split_full_name_trim, :split_full_name])
               |> Ash.read_one!()
    end
  end

  describe "count_nils/1" do
    test "counts nil values" do
      Post
      |> Ash.Changeset.for_create(:create, %{list_containing_nils: ["a", nil, "b", nil, "c"]})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{list_containing_nils: ["a", nil, "b", "c"]})
      |> Ash.create!()

      assert [_] =
               Post
               |> Ash.Query.filter(count_nils(list_containing_nils) == 2)
               |> Ash.read!()
    end
  end

  describe "-/1" do
    test "makes numbers negative" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", score: 42})
      |> Ash.create!()

      assert [%{negative_score: -42}] =
               Post
               |> Ash.Query.load(:negative_score)
               |> Ash.read!()
    end
  end

  describe "maps" do
    test "literal maps inside of conds can be loaded" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match", score: 42})
        |> Ash.create!()

      assert Ash.load!(post, :literal_map_in_expr).literal_map_in_expr == %{
               match: true,
               of: "match"
             }
    end

    test "maps can reference filtered aggregates" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match", score: 42})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "foo", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "foo", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "bar", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert [%{agg_map: %{called_foo: 2, called_bar: 1}}] =
               Post
               |> Ash.Query.load(:agg_map)
               |> Ash.read!()
    end

    test "maps can be constructed" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", score: 42})
      |> Ash.create!()

      assert [%{score_map: %{negative_score: %{foo: -42}}}] =
               Post
               |> Ash.Query.load(:score_map)
               |> Ash.read!()
    end
  end

  describe "at/2" do
    test "selects items by index" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{
          first_name: "Bill ",
          last_name: "Jones ",
          bio: %{title: "Mr.", bio: "Bones"}
        })
        |> Ash.create!()

      assert %{
               first_name_from_split: "Bill"
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load([:first_name_from_split])
               |> Ash.read_one!()
    end
  end

  test "dependent calc" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match", price: 10_024})
      |> Ash.create!()

    Post.get_by_id(post.id,
      query: Post |> Ash.Query.select([:id]) |> Ash.Query.load([:price_string_with_currency_sign])
    )
  end

  test "nested get_path works" do
    assert "thing" =
             Post
             |> Ash.Changeset.for_create(:create, %{
               title: "match",
               price: 10_024,
               stuff: %{foo: %{bar: "thing"}}
             })
             |> Ash.Changeset.deselect(:stuff)
             |> Ash.create!()
             |> Ash.load!(:foo_bar_from_stuff)
             |> Map.get(:foo_bar_from_stuff)
  end

  test "runtime expression calcs" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "Bill",
        last_name: "Jones",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Ash.create!()

    assert %AshPostgres.Test.Money{} =
             Post
             |> Ash.Changeset.for_create(:create, %{title: "match", price: 10_024})
             |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
             |> Ash.create!()
             |> Ash.load!(:calc_returning_json)
             |> Map.get(:calc_returning_json)

    assert [%AshPostgres.Test.Money{}] =
             author
             |> Ash.load!(posts: :calc_returning_json)
             |> Map.get(:posts)
             |> Enum.map(&Map.get(&1, :calc_returning_json))
  end

  test "string_length and string_trim work" do
    Author
    |> Ash.Changeset.for_create(:create, %{
      first_name: "Bill",
      last_name: "Jones",
      bio: %{title: "Mr.", bio: "Bones"}
    })
    |> Ash.create!()

    assert %{calculations: %{length: 9}} =
             Author
             |> Ash.Query.calculate(
               :length,
               :integer,
               expr(string_length(string_trim(first_name <> last_name <> " ")))
             )
             |> Ash.read_one!()
  end

  test "an expression calculation that loads a runtime calculation works" do
    Author
    |> Ash.Changeset.for_create(:create, %{
      first_name: "Bill",
      last_name: "Jones",
      bio: %{title: "Mr.", bio: "Bones"}
    })
    |> Ash.create!()

    assert [%{expr_referencing_runtime: "Bill Jones Bill Jones"}] =
             Author
             |> Ash.Query.load(:expr_referencing_runtime)
             |> Ash.read!()
  end

  test "lazy values are evaluated lazily" do
    Author
    |> Ash.Changeset.for_create(:create, %{
      first_name: "Bill",
      last_name: "Jones",
      bio: %{title: "Mr.", bio: "Bones"}
    })
    |> Ash.create!()

    assert %{calculations: %{string: "fred"}} =
             Author
             |> Ash.Query.calculate(
               :string,
               :string,
               expr(lazy({__MODULE__, :fred, []}))
             )
             |> Ash.read_one!()
  end

  test "binding() can be used to refer to the current binding in a fragment" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    post_id = post.id

    assert [%{id: ^post_id}] =
             Post
             |> Ash.Query.filter(fragment("(?).id", binding()) == type(^post.id, :uuid))
             |> Ash.read!()
  end

  # This test will pass on Ash 3.4.2+
  test "using calculations with input as anonymous aggregate fields works" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "abcdef"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "abc"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "abcd"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "abcde"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    assert %{max_comment_similarity: 0.625} =
             Post
             |> Ash.Query.load(max_comment_similarity: %{to: "abcdef"})
             |> Ash.read_one!()
  end

  test "exists with a relationship that has a filtered read action works" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    post_id = post.id

    assert [%{id: ^post_id}] =
             Post
             |> Ash.Query.filter(has_no_followers)
             |> Ash.read!()
  end

  test "module calculation inside expr calculation works" do
    commedian = Comedian.create!(%{name: "John"})
    commedian = Ash.get!(Comedian, commedian.id, load: [:has_jokes_expr], authorize?: false)
    assert %{has_jokes_expr: false} = commedian
  end

  def fred do
    "fred"
  end

  test "calculation references use the appropriate schema" do
    record = Record |> Ash.Changeset.for_create(:create, %{full_name: "name"}) |> Ash.create!()

    temp_entity =
      TempEntity |> Ash.Changeset.for_create(:create, %{full_name: "name"}) |> Ash.create!()

    Ash.Seed.seed!(RecordTempEntity, %{record_id: record.id, temp_entity_id: temp_entity.id})

    full_name =
      Record
      |> Ash.Query.load(:temp_entity_full_name)
      |> Ash.read_first!()
      |> Map.get(:temp_entity_full_name)

    assert full_name == "name"
  end

  test "calculation with fragment and cond returning integer doesn't cause Postgrex encoding error" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "hello ash lovers"})
    |> Ash.create!()

    assert [%Post{}] =
             Post
             |> Ash.Query.sort("posts_with_matching_title.relevance_score")
             |> Ash.read!()
  end

  test "sorting with filtered relationship by calculated field" do
    tag = Ash.Changeset.for_create(Tag, :create) |> Ash.create!()
    scores = [0, 3, 111, 22, 9, 4, 2, 33, 10]

    scores
    |> Enum.each(fn score ->
      post =
        Ash.Changeset.for_create(Post, :create, %{score: score})
        |> Ash.create!()

      Ash.Changeset.for_create(PostTag, :create, post_id: post.id, tag_id: tag.id)
      |> Ash.create!()
    end)

    post_with_highest_score = Ash.load!(tag, :post_with_highest_score).post_with_highest_score
    highest_score = hd(Enum.sort(scores, :desc))
    assert post_with_highest_score.score == highest_score
  end

  test "an expression calculation can use an aggregate" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "my post"})
      |> Ash.create!()

    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "ashley"
      })
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "first comment"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    first_comment_by_author =
      Comment
      |> Ash.Changeset.for_create(:create, %{title: "first comment by Ashley"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

    post =
      Post
      |> Ash.Query.for_read(:read_by_comment_author, %{
        author_id: author.id
      })
      |> Ash.Query.sort_input([
        {"datetime_of_first_comment_by_author", {%{author_id: author.id}, :desc}}
      ])
      |> Ash.read_one!()

    assert DateTime.compare(
             post.datetime_of_first_comment_by_author,
             first_comment_by_author.created_at
           )
  end

  test "nested calculation with parent() in exists works" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    _post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "test", author_id: author.id})
      |> Ash.create!()

    result =
      Post
      |> Ash.Query.load(:author_has_post_with_title_matching_their_first_name)
      |> Ash.read!()
      |> List.first()

    # Should be false since post title doesn't match author first name
    refute result.author_has_post_with_title_matching_their_first_name
  end

  test "nested calculation with parent() and arguments in exists works" do
    user_id = Ash.UUID.generate()

    # Create a food category
    category =
      AshPostgres.Test.FoodCategory
      |> Ash.Changeset.for_create(:create, %{name: "Dairy"})
      |> Ash.create!()

    # Create a food item in that category
    food_item =
      AshPostgres.Test.FoodItem
      |> Ash.Changeset.for_create(:create, %{
        name: "Cheese",
        food_category_id: category.id
      })
      |> Ash.create!()

    # Create a meal
    meal =
      AshPostgres.Test.Meal
      |> Ash.Changeset.for_create(:create, %{name: "Breakfast"})
      |> Ash.create!()

    # Create a meal item with that food item
    AshPostgres.Test.MealItem
    |> Ash.Changeset.for_create(:create, %{meal_id: meal.id, food_item_id: food_item.id})
    |> Ash.create!()

    # User has not excluded any categories, so meal should be allowed
    result =
      AshPostgres.Test.Meal
      |> Ash.Query.load(allowed_for_user: %{user_id: user_id})
      |> Ash.read_one!()

    assert result.allowed_for_user == true

    # Now exclude the category for the user
    AshPostgres.Test.UserExcludedCategory
    |> Ash.Changeset.for_create(:create, %{
      user_id: user_id,
      food_category_id: category.id
    })
    |> Ash.create!()

    # Now the meal should not be allowed for the user (because it contains an excluded food)
    result =
      AshPostgres.Test.Meal
      |> Ash.Query.load(allowed_for_user: %{user_id: user_id})
      |> Ash.read_one!()

    refute result.allowed_for_user
  end

  test "can filter on nested calculation with parent() and arguments in exists" do
    user_id = Ash.UUID.generate()

    # Create a food category
    category =
      AshPostgres.Test.FoodCategory
      |> Ash.Changeset.for_create(:create, %{name: "Dairy"})
      |> Ash.create!()

    # Create a food item in that category
    food_item =
      AshPostgres.Test.FoodItem
      |> Ash.Changeset.for_create(:create, %{
        name: "Cheese",
        food_category_id: category.id
      })
      |> Ash.create!()

    # Create a meal
    meal =
      AshPostgres.Test.Meal
      |> Ash.Changeset.for_create(:create, %{name: "Breakfast"})
      |> Ash.create!()

    # Create a meal item with that food item
    AshPostgres.Test.MealItem
    |> Ash.Changeset.for_create(:create, %{meal_id: meal.id, food_item_id: food_item.id})
    |> Ash.create!()

    # Exclude the category for the user
    AshPostgres.Test.UserExcludedCategory
    |> Ash.Changeset.for_create(:create, %{
      user_id: user_id,
      food_category_id: category.id
    })
    |> Ash.create!()

    # Filter MealItems by the calculation - this should trigger the parent() binding issue
    query =
      AshPostgres.Test.MealItem
      |> Ash.Query.filter(allowed_for_user(user_id: ^user_id))

    assert [] == Ash.read!(query)
  end

  test "expression calculation referencing aggregates loaded via code_interface with load option" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "test post"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "comment1", likes: 5})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "comment2", likes: 15})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    result = Post.get_by_id!(post.id, load: [:comment_metric])

    assert result.comment_metric == 200
  end

  test "complex SQL fragment calculation with multiple aggregates" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "test post",
        base_reading_time: 500
      })
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "comment1",
      edited_duration: 100,
      planned_duration: 80,
      reading_time: 30,
      version: :edited
    })
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "comment2",
      edited_duration: 0,
      planned_duration: 120,
      reading_time: 45,
      version: :planned
    })
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    result = Post.get_by_id!(post.id, load: [:estimated_reading_time])

    assert result.estimated_reading_time == 175
  end

  test "calculation with missing aggregate dependencies" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "test post",
        base_reading_time: 500
      })
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "modified comment",
      edited_duration: 100,
      planned_duration: 0,
      reading_time: 30,
      version: :edited
    })
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "planned comment",
      edited_duration: 0,
      planned_duration: 80,
      reading_time: 20,
      version: :planned
    })
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    result = Post.get_by_id!(post.id, load: [:estimated_reading_time])

    refute match?(%Ash.NotLoaded{}, result.estimated_reading_time),
           "Expected calculated value, got: #{inspect(result.estimated_reading_time)}"
  end

  test "calculation with filtered aggregates and keyset pagination" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        title: "test post",
        base_reading_time: 500
      })
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "completed comment",
      edited_duration: 100,
      reading_time: 30,
      version: :edited,
      status: :published
    })
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "pending comment",
      planned_duration: 80,
      reading_time: 20,
      version: :planned,
      status: :pending
    })
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    result_both = Post.get_by_id!(post.id, load: [:published_comments, :estimated_reading_time])

    assert result_both.estimated_reading_time == 150,
           "Should calculate correctly with both loaded"

    assert result_both.published_comments == 1, "Should count correctly with both loaded"
  end

  test "calculation with keyset pagination works correctly (previously returned NotLoaded)" do
    _posts =
      Enum.map(1..5, fn i ->
        post =
          Post
          |> Ash.Changeset.for_create(:create, %{
            title: "test post #{i}",
            base_reading_time: 100 * i
          })
          |> Ash.create!()

        Comment
        |> Ash.Changeset.for_create(:create, %{
          title: "comment#{i}",
          edited_duration: 50 * i,
          planned_duration: 40 * i,
          reading_time: 10 * i,
          version: :edited,
          status: :published
        })
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

        post
      end)

    first_page =
      Post
      |> Ash.Query.load([:published_comments, :estimated_reading_time])
      |> Ash.read!(action: :read_with_related_list_agg_filter, page: [limit: 2, count: true])

    Enum.each(first_page.results, fn post ->
      refute match?(%Ash.NotLoaded{}, post.estimated_reading_time),
             "First page post #{post.id} should have loaded estimated_reading_time, got: #{inspect(post.estimated_reading_time)}"
    end)

    if first_page.more? do
      second_page =
        Post
        |> Ash.Query.load([:published_comments, :estimated_reading_time])
        |> Ash.read!(
          action: :read_with_related_list_agg_filter,
          page: [
            limit: 2,
            after: first_page.results |> List.last() |> Map.get(:__metadata__) |> Map.get(:keyset)
          ]
        )

      assert length(second_page.results) > 0, "Second page should have results"

      Enum.each(second_page.results, fn post ->
        refute match?(%Ash.NotLoaded{}, post.estimated_reading_time),
               "estimated_reading_time should be calculated, not NotLoaded"

        refute match?(%Ash.NotLoaded{}, post.published_comments),
               "published_comments should be calculated, not NotLoaded"

        assert post.estimated_reading_time > 0, "estimated_reading_time should be positive"
        assert post.published_comments == 1, "Each post has exactly 1 completed comment"
      end)
    end
  end
end
