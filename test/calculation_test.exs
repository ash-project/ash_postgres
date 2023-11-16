defmodule AshPostgres.CalculationTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Account, Api, Author, Comment, Organization, Post, Profile, User}

  require Ash.Query
  import Ash.Expr

  test "an expression calculation can be filtered on" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

    post2 =
      Post
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

    post3 =
      Post
      |> Ash.Changeset.new(%{title: "title3"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "_"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    post
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post2, post3], type: :append_and_remove)
    |> Api.update!()

    post2
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post3], type: :append_and_remove)
    |> Api.update!()

    assert [%{c_times_p: 6, title: "match"}] =
             Post
             |> Ash.Query.load(:c_times_p)
             |> Api.read!()
             |> Enum.filter(&(&1.c_times_p == 6))

    assert [
             %{c_times_p: %Ash.NotLoaded{}, title: "match"}
           ] =
             Post
             |> Ash.Query.filter(c_times_p == 6)
             |> Api.read!()
  end

  test "calculations can refer to to_one path attributes in filters" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "Foo",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Api.create!()

    assert [%{author_first_name_calc: "Foo"}] =
             Post
             |> Ash.Query.filter(author_first_name_calc == "Foo")
             |> Ash.Query.load(:author_first_name_calc)
             |> Api.read!()
  end

  test "calculations can refer to to_one path attributes in sorts" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "Foo",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Api.create!()

    assert [%{author_first_name_calc: "Foo"}] =
             Post
             |> Ash.Query.sort(:author_first_name_calc)
             |> Ash.Query.load(:author_first_name_calc)
             |> Api.read!()
  end

  test "calculations can refer to embedded attributes" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{bio: %{title: "Mr.", bio: "Bones"}})
      |> Api.create!()

    assert %{title: "Mr."} =
             Author
             |> Ash.Query.filter(id == ^author.id)
             |> Ash.Query.load(:title)
             |> Api.read_one!()
  end

  test "calculations can use the || operator" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{bio: %{title: "Mr.", bio: "Bones"}})
      |> Api.create!()

    assert %{first_name_or_bob: "bob"} =
             Author
             |> Ash.Query.filter(id == ^author.id)
             |> Ash.Query.load(:first_name_or_bob)
             |> Api.read_one!()
  end

  test "calculations can use the && operator" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "fred",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Api.create!()

    assert %{first_name_and_bob: "bob"} =
             Author
             |> Ash.Query.filter(id == ^author.id)
             |> Ash.Query.load(:first_name_and_bob)
             |> Api.read_one!()
  end

  test "calculations can be used in related filters" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Api.create!()

    post2 =
      Post
      |> Ash.Changeset.new(%{title: "title2"})
      |> Api.create!()

    post3 =
      Post
      |> Ash.Changeset.new(%{title: "title3"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "no_match"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Api.create!()

    post
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post2, post3], type: :append_and_remove)
    |> Api.update!()

    post2
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [post3], type: :append_and_remove)
    |> Api.update!()

    posts_query =
      Post
      |> Ash.Query.load(:c_times_p)

    assert %{post: %{c_times_p: 6}} =
             Comment
             |> Ash.Query.load(post: posts_query)
             |> Api.read!()
             |> Enum.filter(&(&1.post.c_times_p == 6))
             |> Enum.at(0)

    query =
      Comment
      |> Ash.Query.filter(post.c_times_p == 6)
      |> Ash.Query.load(post: posts_query)
      |> Ash.Query.limit(1)

    assert [
             %{post: %{c_times_p: 6, title: "match"}}
           ] = Api.read!(query)

    post |> Api.load!(:c_times_p)
  end

  test "concat calculation can be filtered on" do
    author =
      Author
      |> Ash.Changeset.new(%{first_name: "is", last_name: "match"})
      |> Api.create!()

    Author
    |> Ash.Changeset.new(%{first_name: "not", last_name: "match"})
    |> Api.create!()

    author_id = author.id

    assert %{id: ^author_id} =
             Author
             |> Ash.Query.load(:full_name)
             |> Ash.Query.filter(full_name == "is match")
             |> Api.read_one!()
  end

  test "calculations that refer to aggregates in comparison expressions can be filtered on" do
    Post
    |> Ash.Query.load(:has_future_comment)
    |> Api.read!()
  end

  test "conditional calculations can be filtered on" do
    author =
      Author
      |> Ash.Changeset.new(%{first_name: "tom"})
      |> Api.create!()

    Author
    |> Ash.Changeset.new(%{first_name: "tom", last_name: "holland"})
    |> Api.create!()

    author_id = author.id

    assert %{id: ^author_id} =
             Author
             |> Ash.Query.load([:conditional_full_name, :full_name])
             |> Ash.Query.filter(conditional_full_name == "(none)")
             |> Api.read_one!()
  end

  test "parameterized calculations can be filtered on" do
    Author
    |> Ash.Changeset.new(%{first_name: "tom", last_name: "holland"})
    |> Api.create!()

    assert %{param_full_name: "tom holland"} =
             Author
             |> Ash.Query.load(:param_full_name)
             |> Api.read_one!()

    assert %{param_full_name: "tom~holland"} =
             Author
             |> Ash.Query.load(param_full_name: [separator: "~"])
             |> Api.read_one!()

    assert %{} =
             Author
             |> Ash.Query.filter(param_full_name(separator: "~") == "tom~holland")
             |> Api.read_one!()
  end

  test "parameterized related calculations can be filtered on" do
    author =
      Author
      |> Ash.Changeset.new(%{first_name: "tom", last_name: "holland"})
      |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "match"})
    |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
    |> Api.create!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(author.param_full_name(separator: "~") == "tom~holland")
             |> Api.read_one!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(
               author.param_full_name(separator: "~") == "tom~holland" and
                 author.param_full_name(separator: " ") == "tom holland"
             )
             |> Api.read_one!()
  end

  test "parameterized calculations can be sorted on" do
    Author
    |> Ash.Changeset.new(%{first_name: "tom", last_name: "holland"})
    |> Api.create!()

    Author
    |> Ash.Changeset.new(%{first_name: "abc", last_name: "def"})
    |> Api.create!()

    assert [%{first_name: "abc"}, %{first_name: "tom"}] =
             Author
             |> Ash.Query.sort(param_full_name: [separator: "~"])
             |> Api.read!()
  end

  test "calculations using if and literal boolean results can run" do
    Post
    |> Ash.Query.load(:was_created_in_the_last_month)
    |> Ash.Query.filter(was_created_in_the_last_month == true)
    |> Api.read!()
  end

  test "nested conditional calculations can be loaded" do
    Author
    |> Ash.Changeset.new(%{last_name: "holland"})
    |> Api.create!()

    Author
    |> Ash.Changeset.new(%{first_name: "tom"})
    |> Api.create!()

    assert [%{nested_conditional: "No First Name"}, %{nested_conditional: "No Last Name"}] =
             Author
             |> Ash.Query.load(:nested_conditional)
             |> Ash.Query.sort(:nested_conditional)
             |> Api.read!()
  end

  test "calculations load nullable timestamp aggregates compared to a fragment" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "aaa", score: 0})
      |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "aaa", score: 1})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "bbb", score: 0})
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "aaa", likes: 1, arbitrary_timestamp: DateTime.now!("Etc/UTC")})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "bbb", likes: 1})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Comment
    |> Ash.Changeset.new(%{title: "aaa", likes: 2})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Api.create!()

    Post
    |> Ash.Query.load([:has_future_arbitrary_timestamp])
    |> Api.read!()
  end

  test "loading a calculation loads its dependent loads" do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{is_active: true})
      |> Api.create!()

    account =
      Account
      |> Ash.Changeset.for_create(:create, %{is_active: true})
      |> Ash.Changeset.manage_relationship(:user, user, type: :append_and_remove)
      |> Api.create!()
      |> Api.load!([:active])

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
        |> Api.create!()

      assert %{
               full_name_with_nils: "Bill Jones",
               full_name_with_nils_no_joiner: "BillJones"
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load(:full_name_with_nils)
               |> Ash.Query.load(:full_name_with_nils_no_joiner)
               |> Api.read_one!()
    end

    test "with nil value" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{
          first_name: "Bill",
          bio: %{title: "Mr.", bio: "Bones"}
        })
        |> Api.create!()

      assert %{
               full_name_with_nils: "Bill",
               full_name_with_nils_no_joiner: "Bill"
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load(:full_name_with_nils)
               |> Ash.Query.load(:full_name_with_nils_no_joiner)
               |> Api.read_one!()
    end
  end

  test "arguments with cast_in_query?: false are not cast" do
    Post
    |> Ash.Changeset.new(%{title: "match", score: 42})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "not", score: 42})
    |> Api.create!()

    assert [post] =
             Post
             |> Ash.Query.filter(similarity(search: expr(query(search: "match"))))
             |> Api.read!()

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
        |> Api.create!()

      assert %{
               split_full_name: ["Bill", "Jones"]
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load(:split_full_name)
               |> Api.read_one!()
    end

    test "trimming whitespace" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{
          first_name: "Bill ",
          last_name: "Jones ",
          bio: %{title: "Mr.", bio: "Bones"}
        })
        |> Api.create!()

      assert %{
               split_full_name_trim: ["Bill", "Jones"],
               split_full_name: ["Bill", "Jones"]
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load([:split_full_name_trim, :split_full_name])
               |> Api.read_one!()
    end
  end

  describe "-/1" do
    test "makes numbers negative" do
      Post
      |> Ash.Changeset.new(%{title: "match", score: 42})
      |> Api.create!()

      assert [%{negative_score: -42}] =
               Post
               |> Ash.Query.load(:negative_score)
               |> Api.read!()
    end
  end

  describe "maps" do
    test "maps can reference filtered aggregats" do
      post =
        Post
        |> Ash.Changeset.new(%{title: "match", score: 42})
        |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "foo", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "foo", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      Comment
      |> Ash.Changeset.new(%{title: "bar", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Api.create!()

      assert [%{agg_map: %{called_foo: 2, called_bar: 1}}] =
               Post
               |> Ash.Query.load(:agg_map)
               |> Api.read!()
    end

    test "maps can be constructed" do
      Post
      |> Ash.Changeset.new(%{title: "match", score: 42})
      |> Api.create!()

      assert [%{score_map: %{negative_score: %{foo: -42}}}] =
               Post
               |> Ash.Query.load(:score_map)
               |> Api.read!()
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
        |> Api.create!()

      assert %{
               first_name_from_split: "Bill"
             } =
               Author
               |> Ash.Query.filter(id == ^author.id)
               |> Ash.Query.load([:first_name_from_split])
               |> Api.read_one!()
    end
  end

  test "dependent calc" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "match", price: 10_024})
      |> Api.create!()

    Post.get_by_id(post.id,
      query: Post |> Ash.Query.select([:id]) |> Ash.Query.load([:price_string_with_currency_sign])
    )
  end

  test "nested get_path works" do
    assert "thing" =
             Post
             |> Ash.Changeset.new(%{title: "match", price: 10_024, stuff: %{foo: %{bar: "thing"}}})
             |> Ash.Changeset.deselect(:stuff)
             |> Api.create!()
             |> Api.load!(:foo_bar_from_stuff)
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
      |> Api.create!()

    assert %AshPostgres.Test.Money{} =
             Post
             |> Ash.Changeset.new(%{title: "match", price: 10_024})
             |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
             |> Api.create!()
             |> Api.load!(:calc_returning_json)
             |> Map.get(:calc_returning_json)

    assert [%AshPostgres.Test.Money{}] =
             author
             |> Api.load!(posts: :calc_returning_json)
             |> Map.get(:posts)
             |> Enum.map(&Map.get(&1, :calc_returning_json))
  end

  @tag :focus
  test "calculation passes actor to aggregate from calculation on aggregate" do
    org =
      Organization
      |> Ash.Changeset.new(%{name: "The Org"})
      |> Api.create!()

    user =
      User
      |> Ash.Changeset.for_create(:create, %{is_active: true})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
      |> Api.create!()

    profile =
      Profile
      |> Ash.Changeset.for_create(:create, %{description: "Prolific describer of worlds..."})
      |> Api.create!()

    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "Foo",
        bio: %{title: "Mr.", bio: "Bones"}
      })
      |> Ash.Changeset.manage_relationship(:profile, profile, type: :append)
      |> Api.create!()

    created_post =
      Post
      |> Ash.Changeset.new(%{title: "match"})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Api.create!()

    can_get_author_description_post =
      Post
      |> Ash.Query.filter(id == ^created_post.id)
      |> Ash.Query.load(author: :description)
      |> Api.read_one!(actor: user)

    assert can_get_author_description_post.author.description == "actor"

    can_get_author_description_from_aggregate_post =
      Post
      |> Ash.Query.filter(id == ^created_post.id)
      |> Ash.Query.load(:author_profile_description)
      |> Api.read_one!(actor: user)

    assert can_get_author_description_from_aggregate_post.author_profile_description ==
             "Prolific describer of worlds..."

    can_get_author_description_from_calculation_of_aggregate_post =
      Post
      |> Ash.Query.filter(id == ^created_post.id)
      |> Ash.Query.load(:author_profile_description_from_agg)
      |> Api.read_one!(actor: user)

    assert can_get_author_description_from_calculation_of_aggregate_post.author_profile_description_from_agg ==
             "Prolific describer of worlds..."
  end
end
