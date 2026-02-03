# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.AtomicsTest do
  alias AshPostgres.Test.Author
  alias AshPostgres.Test.Comment

  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.Invite
  alias AshPostgres.Test.Post
  alias AshPostgres.Test.User

  import Ash.Expr
  require Ash.Query

  test "atomics work on upserts" do
    id = Ash.UUID.generate()

    Post
    |> Ash.Changeset.for_create(:create, %{id: id, title: "foo", price: 1}, upsert?: true)
    |> Ash.Changeset.atomic_update(:price, expr(price + 1))
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{id: id, title: "foo", price: 1}, upsert?: true)
    |> Ash.Changeset.atomic_update(:price, expr(price + 1))
    |> Ash.create!()

    assert [%{price: 2}] = Post |> Ash.read!()
  end

  test "a basic atomic works" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert %{price: 2} =
             post
             |> Ash.Changeset.for_update(:update, %{})
             |> Ash.Changeset.atomic_update(:price, expr(price + 1))
             |> Ash.update!()
  end

  test "an atomic update on decimals works" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", decimal: Decimal.new("1")})
      |> Ash.create!()

    assert %{decimal: result} =
             post
             |> Ash.Changeset.for_update(:subtract_integer_from_decimal, %{amount: 2})
             |> Ash.update!()

    assert Decimal.eq?(result, Decimal.new("-1"))

    assert %{decimal: result} =
             post
             |> Ash.Changeset.for_update(:subtract_from_decimal, %{amount: Decimal.new("2")})
             |> Ash.update!()

    assert Decimal.eq?(result, Decimal.new("-3"))
  end

  test "an atomic works on a constrained integer" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert %{limited_score: 6} =
             post
             |> Ash.Changeset.for_update(:add_to_limited_score, %{amount: 6})
             |> Ash.update!()
  end

  test "an atomic works on an array attribute" do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.create!()

    assert %{role_list: [:admin]} =
             user
             |> Ash.Changeset.for_update(:add_role, %{role: :admin})
             |> Ash.update!()
  end

  test "a basic atomic works with enum/allow_nil? false" do
    user =
      User
      |> Ash.Changeset.for_create(:create, %{name: "Dude", role: :user})
      |> Ash.create!()

    Invite
    |> Ash.Changeset.for_create(:create, %{
      name: "Dude",
      role: :admin
    })
    |> Ash.create!()

    assert %{role: :admin} =
             user
             |> Ash.Changeset.for_update(:accept_invite, %{})
             |> Ash.update!()
  end

  test "atomics work with maps that contain lists" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert %{list_of_stuff: [%{"foo" => [%{"a" => 1}]}]} =
             post
             |> Ash.Changeset.for_update(:update, %{list_of_stuff: [%{foo: [%{a: 1}]}]})
             |> Ash.update!()
  end

  test "atomics work with maps that contain lists that contain maps that contain lists etc." do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert %{list_of_stuff: [%{"foo" => [%{"a" => 1, "b" => %{"c" => [1, 2, 3]}}]}]} =
             post
             |> Ash.Changeset.for_update(:update, %{
               list_of_stuff: [%{foo: [%{a: 1, b: %{c: [1, 2, 3]}}]}]
             })
             |> Ash.update!()
  end

  test "atomics work with maps that contain expressions in a deep structure" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert %{list_of_stuff: [%{"foo" => [%{"a" => 1, "b" => %{"c" => [1, 2, 3]}}]}]} =
             post
             |> Ash.Changeset.for_update(:update, %{})
             |> Ash.Changeset.atomic_update(%{
               list_of_stuff:
                 {:atomic,
                  [
                    %{foo: [%{a: 1, b: %{c: [1, 2, expr(type(fragment("3"), :integer))]}}]}
                  ]}
             })
             |> Ash.update!()
  end

  test "an atomic update can be set to the value of an aggregate" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bar", author_id: author.id})
      |> Ash.create!()

    # just asserting that there is no exception here
    post
    |> Ash.Changeset.for_update(:set_title_to_sum_of_author_count_of_posts)
    |> Ash.update!()
  end

  test "an atomic update can be set to the value of a related aggregate" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bar", author_id: author.id})
      |> Ash.create!()

    # just asserting that there is no exception here
    post
    |> Ash.Changeset.for_update(:set_title_to_author_profile_description)
    |> Ash.update!()
  end

  test "an atomic validation is based on where it appears in the action" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bar"})
      |> Ash.create!()

    # just asserting that there is no exception here
    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.limit(1)
    |> Ash.bulk_update!(:change_title_to_foo_unless_its_already_foo, %{})
  end

  test "an atomic validation can refer to an attribute being cast atomically" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bar"})
      |> Ash.create!()

    # just asserting that there is no exception here
    Post
    |> Ash.Query.filter(id == ^post.id)
    |> Ash.Query.limit(1)
    |> Ash.bulk_update!(:update_constrained_int, %{amount: 4})
  end

  test "an atomic validation can refer to an attribute being cast atomically, and will raise an error" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bar"})
      |> Ash.create!()

    # just asserting that there is no exception here
    assert_raise Ash.Error.Invalid, ~r/must be less than or equal to 10/, fn ->
      Post
      |> Ash.Query.filter(id == ^post.id)
      |> Ash.Query.limit(1)
      |> Ash.bulk_update!(:update_constrained_int, %{amount: 12})
    end

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "bar", constrained_int: 5})
      |> Ash.create!()

    assert %{constrained_int: 10} = Post.update_constrained_int!(post.id, 5)
  end

  test "an atomic works with a datetime" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    now = DateTime.utc_now()

    assert %{created_at: ^now} =
             post
             |> Ash.Changeset.new()
             |> Ash.Changeset.atomic_update(:created_at, expr(^now))
             |> Ash.Changeset.for_update(:update, %{})
             |> Ash.update!()
  end

  test "an atomic that violates a constraint will return the proper error" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert_raise Ash.Error.Invalid, ~r/does not exist/, fn ->
      post
      |> Ash.Changeset.new()
      |> Ash.Changeset.atomic_update(:organization_id, Ash.UUID.generate())
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.update!()
    end
  end

  test "an atomic can refer to a calculation" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    post =
      post
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.atomic_update(:score, expr(score_after_winning))
      |> Ash.update!()

    assert post.score == 1
  end

  test "an atomic can be attached to an action" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
      |> Ash.create!()

    assert Post.increment_score!(post, 2).score == 2

    assert Post.increment_score!(post, 2).score == 4
  end

  test "relationships can be used in atomic update" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{
        first_name: "John",
        last_name: "Doe"
      })
      |> Ash.create!()

    parent_post =
      Post
      |> Ash.Changeset.for_create(:create, %{price: 42, author_id: author.id})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{
        price: 1,
        author_id: author.id,
        parent_post_id: parent_post.id
      })
      |> Ash.create!()

    post =
      post
      |> Ash.Changeset.for_update(:set_title_from_author, %{})
      |> Ash.update!()

    assert post.title == "John"

    post =
      post
      |> Ash.Changeset.for_update(:set_attributes_from_parent, %{})
      |> Ash.update!()

    assert post.title == "John"
  end

  test "relationships can be used in atomic update and in an atomic update filter" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{price: 1, author_id: author.id})
    |> Ash.create!()

    post =
      Post
      |> Ash.Query.filter(author.last_name == "Doe")
      |> Ash.bulk_update!(:set_title_from_author, %{}, return_records?: true)
      |> Map.get(:records)
      |> List.first()

    assert post.title == "John"
  end

  test "relationships can be used in atomic update and in an atomic update filter when first join is a left join" do
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{price: 1, author_id: author.id})
    |> Ash.create!()

    assert [] =
             Post
             |> Ash.Query.filter(is_nil(author.last_name))
             |> Ash.bulk_update!(:set_title_from_author, %{}, return_records?: true)
             |> Map.get(:records)
  end

  Enum.each(
    [
      :exists
      # :list,
      # :count,
      # :combined
    ],
    fn aggregate ->
      test "can use #{aggregate} in validation" do
        post =
          Post
          |> Ash.Changeset.for_create(:create, %{title: "foo", price: 1})
          |> Ash.create!()

        Comment
        |> Ash.Changeset.for_create(:create, %{post_id: post.id, title: "foo"})
        |> Ash.create!()

        assert_raise Ash.Error.Invalid, ~r/Can only update if Post has no comments/, fn ->
          post
          |> Ash.Changeset.new()
          |> Ash.Changeset.put_context(:aggregate, unquote(aggregate))
          |> Ash.Changeset.for_update(:update_if_no_comments, %{title: "bar"})
          |> Ash.update!()
        end

        assert_raise Ash.Error.Invalid, ~r/Can only update if Post has no comments/, fn ->
          post
          |> Ash.Changeset.new()
          |> Ash.Changeset.put_context(:aggregate, unquote(aggregate))
          |> Ash.Changeset.for_update(:update_if_no_comments_non_atomic, %{title: "bar"})
          |> Ash.update!()
        end

        assert_raise Ash.Error.Invalid, ~r/Can only delete if Post has no comments/, fn ->
          post
          |> Ash.Changeset.new()
          |> Ash.Changeset.put_context(:aggregate, unquote(aggregate))
          |> Ash.Changeset.for_destroy(:destroy_if_no_comments_non_atomic, %{})
          |> Ash.destroy!()
        end

        assert_raise Ash.Error.Invalid, ~r/Can only delete if Post has no comments/, fn ->
          post
          |> Ash.Changeset.new()
          |> Ash.Changeset.put_context(:aggregate, unquote(aggregate))
          |> Ash.Changeset.for_destroy(:destroy_if_no_comments, %{})
          |> Ash.destroy!()
        end
      end
    end
  )

  describe "atomic create (create_atomics)" do
    # Tests for atomic_set on create actions - supported in Ash 3.14+

    test "atomic_set works on create with fragment subquery" do
      # Create 3 initial posts
      Enum.each(1..3, fn i ->
        Post
        |> Ash.Changeset.for_create(:create, %{title: "post_#{i}", price: i})
        |> Ash.create!()
      end)

      # Use atomic_set to set score to count of existing posts
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "new_post", price: 10})
        |> Ash.Changeset.atomic_set(
          :score,
          expr(fragment("(SELECT count(*) FROM posts WHERE type = 'sponsored')"))
        )
        |> Ash.create!()

      # Score should be 3 (count of existing sponsored posts when INSERT ran)
      assert post.score == 3
    end

    test "atomic_set works on create with simple literal expression" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "test", price: 5})
        |> Ash.Changeset.atomic_set(:score, expr(42))
        |> Ash.create!()

      assert post.score == 42
    end

    test "atomic_set works on create with arithmetic expression" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "test", price: 10})
        |> Ash.Changeset.atomic_set(:score, expr(5 + 15))
        |> Ash.create!()

      assert post.score == 20
    end

    test "atomic_set on create overrides attributes when both are set" do
      # If both attributes and atomic_set set a value, atomics should win
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "test", price: 5, score: 999})
        |> Ash.Changeset.atomic_set(:score, expr(100))
        |> Ash.create!()

      # The atomic expression should override the attribute value
      assert post.score == 100
    end

    test "atomic_set on create works sequentially" do
      # Create 2 initial posts
      Enum.each(1..2, fn i ->
        Post
        |> Ash.Changeset.for_create(:create, %{title: "initial_#{i}", price: i})
        |> Ash.create!()
      end)

      # Create posts one by one with atomic_set
      results =
        Enum.map(1..3, fn i ->
          Post
          |> Ash.Changeset.for_create(:create, %{title: "new_#{i}", price: i})
          |> Ash.Changeset.atomic_set(
            :score,
            expr(fragment("(SELECT count(*) FROM posts WHERE type = 'sponsored')"))
          )
          |> Ash.create!()
        end)

      # First post sees 2 existing posts
      assert Enum.at(results, 0).score == 2
      # Subsequent posts see incrementing counts
      assert Enum.at(results, 1).score == 3
      assert Enum.at(results, 2).score == 4
    end
  end
end
