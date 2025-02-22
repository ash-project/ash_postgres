defmodule AshPostgres.CalculationTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Account, Author, Comedian, Comment, Post, User}

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
end
