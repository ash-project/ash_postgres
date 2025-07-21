defmodule AshSql.AggregateTest do
  use AshPostgres.RepoCase, async: false
  alias AshPostgres.Test.{Author, Comment, Organization, Post, Rating, User}

  require Ash.Query
  import Ash.Expr

  test "nested sum aggregates" do
    # asserting an error is not raised
    assert Post
           |> Ash.Query.load(:sum_of_comment_ratings_calc)
           |> Ash.read!() == []
  end

  test "count aggregate on no cast enum field" do
    Organization |> Ash.read!(load: [:no_cast_open_posts_count])
  end

  test "count aggregate on resource with no primary key with no field specified" do
    assert Ash.count!(AshPostgres.Test.PostView) == 0
  end

  test "can sum count aggregates" do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "The Org"})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    assert Decimal.eq?(Ash.sum!(Post, :count_of_comments), Decimal.new("2"))
  end

  test "relates to actor via has_many and with an aggregate" do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "The Org"})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
      |> Ash.create!()

    user =
      User
      |> Ash.Changeset.for_create(:create, %{})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    read_post =
      Post
      |> Ash.Query.filter(id == ^post.id)
      |> Ash.read_one!(actor: user)

    assert read_post.id == post.id

    read_post =
      Post
      |> Ash.Query.filter(id == ^post.id)
      |> Ash.Query.load(:count_of_comments)
      |> Ash.read_one!(actor: user)

    assert read_post.count_of_comments == 1

    read_post =
      post
      |> Ash.load!(:count_of_comments, actor: user)

    assert read_post.count_of_comments == 1
  end

  test "nested filters on aggregates works" do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "match"})
      |> Ash.create!()

    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:organization, org, type: :append_and_remove)
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    assert [%{count_of_comments_matching_org_name: 1}] =
             Post
             |> Ash.Query.load(:count_of_comments_matching_org_name)
             |> Ash.Query.filter(id == ^post.id)
             |> Ash.read!()
  end

  describe "Context Multitenancy" do
    alias AshPostgres.MultitenancyTest.{Org, Post, User}

    test "aggregating with a filter on an aggregate honors the tenant" do
      org =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "BTTF"})
        |> Ash.create!()

      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Marty", org_id: org.id})
        |> Ash.create!()

      ["Back to 1955", "Forwards to 1985", "Forward to 2015", "Back again to 1985"]
      |> Enum.map(
        &(Post
          |> Ash.Changeset.for_create(:create, %{name: &1, user_id: user.id})
          |> Ash.create!(tenant: "org_#{org.id}", load: [:last_word]))
      )

      assert 1 ==
               User
               |> Ash.Query.set_tenant("org_#{org.id}")
               |> Ash.Query.filter(count_visited > 1)
               |> Ash.Query.load(:count_visited)
               |> Ash.count!()
    end

    test "loading a nested aggregate honors tenant" do
      alias AshPostgres.MultitenancyTest.{Org, Post, User}

      org =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "BTTF"})
        |> Ash.create!()

      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Marty", org_id: org.id})
        |> Ash.create!()

      ["Back to 1955", "Forwards to 1985", "Forward to 2015", "Back again to 1985"]
      |> Enum.map(
        &(Post
          |> Ash.Changeset.for_create(:create, %{name: &1, user_id: user.id})
          |> Ash.create!(tenant: "org_#{org.id}", load: [:last_word]))
      )

      assert Ash.load!(user, :count_visited, tenant: "org_#{org.id}")
             |> then(& &1.count_visited) == 4

      assert Ash.load!(org, :total_posts, tenant: "org_#{org.id}")
             |> then(& &1.total_posts) == 0

      assert Ash.load!(org, :total_users_posts, tenant: "org_#{org.id}")
             |> then(& &1.total_users_posts) == 4
    end
  end

  describe "join filters" do
    test "with no data, it does not effect the behavior" do
      Author
      |> Ash.Changeset.for_create(:create)
      |> Ash.create!()

      assert [%{count_of_posts_with_better_comment: 0}] =
               Author
               |> Ash.Query.load(:count_of_posts_with_better_comment)
               |> Ash.read!()
    end

    test "it properly applies join criteria" do
      author =
        Author
        |> Ash.Changeset.for_create(:create)
        |> Ash.create!()

      matching_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "match", score: 10})
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      non_matching_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "non_match", score: 100})
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 100})
      |> Ash.Changeset.manage_relationship(:post, matching_post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "non_match", likes: 0})
      |> Ash.Changeset.manage_relationship(:post, non_matching_post, type: :append_and_remove)
      |> Ash.create!()

      assert [%{count_of_posts_with_better_comment: 1}] =
               Author
               |> Ash.Query.load(:count_of_posts_with_better_comment)
               |> Ash.read!()
    end

    test "it properly applies join criteria to exists queries in filters" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create!()

      non_matching_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "non_match", score: 100})
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "non_match", likes: 0})
      |> Ash.Changeset.manage_relationship(:post, non_matching_post, type: :append_and_remove)
      |> Ash.create!()

      assert [] =
               Author
               |> Ash.Query.filter(has_post_with_better_comment)
               |> Ash.read!()
    end
  end

  describe "count" do
    test "with no related data it returns 0" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      assert %{count_of_comments: 0} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments)
               |> Ash.read_one!()
    end

    test "with data and a custom aggregate, it returns the count" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{aggregates: %{custom_count_of_comments: 1}} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.aggregate(
                 :custom_count_of_comments,
                 :count,
                 :comments,
                 query: [filter: expr(not is_nil(title))]
               )
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{aggregates: %{custom_count_of_comments: 2}} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.aggregate(
                 :custom_count_of_comments,
                 :count,
                 :comments,
                 query: [filter: expr(not is_nil(title))]
               )
               |> Ash.read_one!()
    end

    test "with data and a custom string keyed aggregate, it returns the count" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{aggregates: %{"custom_count_of_comments" => 1}} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.aggregate(
                 "custom_count_of_comments",
                 :count,
                 :comments,
                 query: [filter: expr(not is_nil(title))]
               )
               |> Ash.read_one!()
    end

    test "with data for a many_to_many, it returns the count" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title2"})
        |> Ash.create!()

      post3 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title3"})
        |> Ash.create!()

      post
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:linked_posts, [post2, post3],
        type: :append_and_remove
      )
      |> Ash.update!()

      post2
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:linked_posts, [post3], type: :append_and_remove)
      |> Ash.update!()

      assert [
               %{count_of_linked_posts: 2, title: "title"},
               %{count_of_linked_posts: 1, title: "title2"}
             ] =
               Post
               |> Ash.Query.load(:count_of_linked_posts)
               |> Ash.Query.filter(count_of_linked_posts >= 1)
               |> Ash.Query.sort(count_of_linked_posts: :desc)
               |> Ash.read!()
    end

    test "with data and a filter, it returns the count" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{count_of_comments_called_match: 1} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments_called_match)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "not_match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{count_of_comments_called_match: 1} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:count_of_comments_called_match)
               |> Ash.read_one!()
    end
  end

  describe "exists" do
    test "with data and a filter, it returns the correct result" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "non-match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{has_comment_called_match: false} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:has_comment_called_match)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{has_comment_called_match: true} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:has_comment_called_match)
               |> Ash.read_one!()
    end

    test "exists aggregates can be referenced in filters" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      refute Post
             |> Ash.Query.filter(has_comment_called_match)
             |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{has_comment_called_match: true} =
               Post
               |> Ash.Query.filter(has_comment_called_match)
               |> Ash.Query.load(:has_comment_called_match)
               |> Ash.read_one!()
    end

    test "exists aggregates can be referenced in nested filters" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert Comment
             |> Ash.Query.filter(post.has_comment_called_match)
             |> Ash.read_one!()
    end

    test "exists aggregates can be used at the query level" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "title2"})
      |> Ash.create!()

      refute Post
             |> Ash.Query.filter(has_comment_called_match)
             |> Ash.exists?()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert Post |> Ash.exists?()

      refute Post |> Ash.exists?(query: [filter: [title: "non-match"]])
    end
  end

  describe "list" do
    test "with no related data it returns an empty list" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      assert %{comment_titles: []} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles)
               |> Ash.read_one!()
    end

    test "does not return nil values" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "bbb"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: nil})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "aaa"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{comment_titles: ["aaa", "bbb"]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles)
               |> Ash.read_one!()
    end

    @tag :postgres_16
    test "returns nil values if `include_nil?` is set to `true`" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "bbb"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: nil})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "aaa"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{comment_titles_with_nils: ["aaa", "bbb", nil]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles_with_nils)
               |> Ash.read_one!()
    end

    test "with related data, it returns the value" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "bbb"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "ccc"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{comment_titles: ["bbb", "ccc"]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "aaa"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{comment_titles: ["aaa", "bbb", "ccc"]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:comment_titles)
               |> Ash.read_one!()
    end

    test "with related data, it returns the uniq" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "aaa"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "aaa"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{uniq_comment_titles: ["aaa"]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:uniq_comment_titles)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "bbb"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{uniq_comment_titles: ["aaa", "bbb"]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:uniq_comment_titles)
               |> Ash.read_one!()

      assert %{count_comment_titles: 3, count_uniq_comment_titles: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load([:count_comment_titles, :count_uniq_comment_titles])
               |> Ash.read_one!()
    end

    test "when related data that uses schema-based multitenancy, it returns the uniq" do
      alias AshPostgres.MultitenancyTest.{Org, Post, User}

      org =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "BTTF"})
        |> Ash.create!()

      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Marty", org_id: org.id})
        |> Ash.create!()

      ["Back to 1955", "Forwards to 1985", "Forward to 2015", "Back again to 1985"]
      |> Enum.map(
        &(Post
          |> Ash.Changeset.for_create(:create, %{name: &1, user_id: user.id})
          |> Ash.create!(tenant: "org_#{org.id}", load: [:last_word]))
      )

      user = Ash.load!(user, :years_visited, tenant: "org_#{org.id}")

      assert Enum.sort(user.years_visited) == ["1955", "1985", "1985", "2015"]
    end
  end

  describe "first" do
    test "with no related data it returns nil" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      assert %{first_comment: nil} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment)
               |> Ash.read_one!()
    end

    test "with related data, it returns the value" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{first_comment: "match"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "early match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{first_comment: "early match"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment)
               |> Ash.read_one!()
    end

    test "it does not return `nil` values by default" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: nil})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{first_comment_nils_first: "match"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment_nils_first)
               |> Ash.read_one!()
    end

    test "it does not return `nil` values when filtered" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: nil})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "stuff"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{first_comment_nils_first_called_stuff: "stuff"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load([
                 :first_comment_nils_first_called_stuff,
                 :first_comment_nils_first
               ])
               |> Ash.read_one!()
    end

    @tag :postgres_16
    test "it returns `nil` values when `include_nil?` is `true`" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: nil})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert "match" ==
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:first_comment_nils_first_include_nil)
               |> Ash.read_one!()
               |> Map.get(:first_comment_nils_first_include_nil)
    end

    test "it can be sorted on" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      post_id = post.id

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      post_2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "zed"})
      |> Ash.Changeset.manage_relationship(:post, post_2, type: :append_and_remove)
      |> Ash.create!()

      assert %{id: ^post_id} =
               Post
               |> Ash.Query.sort(:first_comment)
               |> Ash.Query.limit(1)
               |> Ash.read_one!()
    end

    test "first aggregates can be sorted on" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "first name"})
        |> Ash.create!()

      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      assert %{author_first_name: "first name"} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:author_first_name)
               |> Ash.Query.sort(author_first_name: :asc)
               |> Ash.read_one!()
    end

    test "aggregate maintains datetime precision" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "first name"})
        |> Ash.create!()

      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      latest_comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      fetched_post =
        Post
        |> Ash.Query.filter(id == ^post.id)
        |> Ash.Query.load(:latest_comment_created_at)
        |> Ash.read_one!()

      assert latest_comment.created_at == fetched_post.latest_comment_created_at
    end

    test "it can be sorted on and produces the appropriate order" do
      post1 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:post, post1, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "c"})
      |> Ash.Changeset.manage_relationship(:post, post1, type: :append_and_remove)
      |> Ash.create!()

      post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "a"})
      |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
      |> Ash.create!()

      post3 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "c"})
      |> Ash.Changeset.manage_relationship(:post, post3, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "d"})
      |> Ash.Changeset.manage_relationship(:post, post3, type: :append_and_remove)
      |> Ash.create!()

      assert [%{last_comment: "d"}, %{last_comment: "c"}] =
               Post
               |> Ash.Query.load(:last_comment)
               |> Ash.Query.sort(last_comment: :desc)
               |> Ash.Query.filter(not is_nil(comments.title))
               |> Ash.Query.limit(2)
               |> Ash.read!()
    end
  end

  test "sum aggregates show the same value with filters on the sum vs filters on relationships" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    for i <- 1..5 do
      ratings =
        for i <- [3, 5, 7, 9] do
          %{score: i}
        end

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title#{i}"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.Changeset.manage_relationship(:ratings, ratings, type: :create)
      |> Ash.create!()
    end

    values =
      post
      |> Ash.load!([
        :sum_of_popular_comment_rating_scores_2
      ])
      |> Map.take([:sum_of_popular_comment_rating_scores_2])

    assert %{sum_of_popular_comment_rating_scores_2: 80} =
             values

    values =
      post
      |> Ash.load!([
        :sum_of_odd_comment_rating_scores
      ])
      |> Map.take([:sum_of_odd_comment_rating_scores])

    assert %{sum_of_odd_comment_rating_scores: 120} =
             values
  end

  test "can't define multidimensional array aggregate types" do
    assert_raise Spark.Error.DslError, ~r/Aggregate not supported/, fn ->
      defmodule Foo do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          data_layer: AshPostgres.DataLayer

        postgres do
          table("profile")
          repo(AshPostgres.TestRepo)
        end

        attributes do
          uuid_primary_key(:id, writable?: true)
        end

        actions do
          defaults([:create, :read, :update, :destroy])
        end

        relationships do
          belongs_to(:author, AshPostgres.Test.Author) do
            public?(true)
          end
        end

        aggregates do
          first(:author_badges, :author, :badges)
        end
      end
    end
  end

  test "related aggregates can be filtered on" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "non_match"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "non_match2"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    assert %{title: "match"} =
             Comment
             |> Ash.Query.filter(post.count_of_comments == 1)
             |> Ash.read_one!()
  end

  @tag :regression
  test "aggregates with parent expressions in their filters are not grouped" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "something else"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    assert %{count_of_comments: 2, count_of_comments_with_same_name: 1} =
             post
             |> Ash.load!([:count_of_comments, :count_of_comments_with_same_name])
  end

  describe "sum" do
    test "with no related data it returns nil" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      assert %{sum_of_comment_likes: nil} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes)
               |> Ash.read_one!()
    end

    test "with no related data and a default it returns the default" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      assert %{sum_of_comment_likes_with_default: 0} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_with_default)
               |> Ash.read_one!()
    end

    test "with data, it returns the sum" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{sum_of_comment_likes: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 3})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{sum_of_comment_likes: 5} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes)
               |> Ash.read_one!()
    end

    test "with data and a filter, it returns the sum" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{sum_of_comment_likes_called_match: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "not_match", likes: 3})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{sum_of_comment_likes_called_match: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Ash.read_one!()
    end

    test "filtering on a nested aggregate works" do
      Post
      |> Ash.Query.filter(count_of_comment_ratings == 0)
      |> Ash.read!()
    end

    test "nested aggregates show the proper values" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      author =
        AshPostgres.Test.Author
        |> Ash.Changeset.for_create(:create, %{"first_name" => "ted"})
        |> Ash.create!()

      comment1 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      comment2 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
        |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 5, resource_id: comment1.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 10, resource_id: comment2.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      assert [%{count_of_comment_ratings: 2}] =
               Post |> Ash.Query.load(:count_of_comment_ratings) |> Ash.read!()

      assert [%{highest_comment_rating: 10}] =
               Post |> Ash.Query.load(:highest_comment_rating) |> Ash.read!()

      assert [%{lowest_comment_rating: 5}] =
               Post |> Ash.Query.load(:lowest_comment_rating) |> Ash.read!()

      assert [%{avg_comment_rating: 7.5}] =
               Post |> Ash.Query.load(:avg_comment_rating) |> Ash.read!()

      # TODO: want to add an option for `unique` here at some point
      assert [%{comment_authors: "ted,ted"}] =
               Post |> Ash.Query.load(:comment_authors) |> Ash.read!()
    end

    test "nested filtered aggregates show the proper values" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      comment1 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      comment2 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 20, resource_id: comment1.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 1, resource_id: comment2.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      assert [%{count_of_comment_ratings: 2, count_of_popular_comment_ratings: 1}] =
               Post
               |> Ash.Query.load([:count_of_comment_ratings, :count_of_popular_comment_ratings])
               |> Ash.read!()

      assert [%{count_of_comment_ratings: 2}] =
               Post
               |> Ash.Query.load([:count_of_comment_ratings])
               |> Ash.read!()

      assert [%{count_of_popular_comment_ratings: 1}] =
               Post
               |> Ash.Query.load([:count_of_popular_comment_ratings])
               |> Ash.read!()
    end

    test "nested filtered and sorted aggregates show the proper values" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      comment1 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      comment2 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 20, resource_id: comment1.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 1, resource_id: comment2.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      assert [%{count_of_comment_ratings: 2, count_of_popular_comment_ratings: 1}] =
               Post
               |> Ash.Query.load([:count_of_comment_ratings, :count_of_popular_comment_ratings])
               |> Ash.read!()
    end

    test "nested first aggregate works" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "title", likes: 2})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 10, resource_id: comment.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      post =
        Post
        |> Ash.Query.load(:highest_rating)
        |> Ash.read!()
        |> Enum.at(0)

      assert post.highest_rating == 10
    end

    test "loading a nested aggregate works" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "title", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Query.load(:count_of_comment_ratings)
      |> Ash.read!()
      |> Enum.map(fn post ->
        assert post.count_of_comment_ratings == 0
      end)
    end

    test "the sum can be filtered on when paginating" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 2})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %{sum_of_comment_likes_called_match: 2} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Ash.read_one!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "not_match", likes: 3})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %Ash.Page.Offset{results: [%{sum_of_comment_likes_called_match: 2}]} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Ash.Query.filter(sum_of_comment_likes_called_match == 2)
               |> Ash.read!(action: :paginated, page: [limit: 1, count: true])

      assert %Ash.Page.Offset{results: []} =
               Post
               |> Ash.Query.filter(id == ^post.id)
               |> Ash.Query.load(:sum_of_comment_likes_called_match)
               |> Ash.Query.filter(sum_of_comment_likes_called_match == 3)
               |> Ash.read!(action: :paginated, page: [limit: 1, count: true])
    end

    test "an aggregate on relationships with a filter returns the proper value" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title", category: "foo"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 20})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 17})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 50})
      |> Ash.Changeset.force_change_attribute(
        :created_at,
        DateTime.add(DateTime.utc_now(), :timer.hours(24) * -20, :second)
      )
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %Post{sum_of_recent_popular_comment_likes: 37} =
               Post
               |> Ash.Query.load(:sum_of_recent_popular_comment_likes)
               |> Ash.read_one!()
    end

    test "a count aggregate on relationships with a filter returns the proper value" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title", category: "foo"})
        |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 20})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 17})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "match", likes: 50})
      |> Ash.Changeset.force_change_attribute(
        :created_at,
        DateTime.add(DateTime.utc_now(), :timer.hours(24) * -20, :second)
      )
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      assert %Post{count_of_recent_popular_comments: 2} =
               Post
               |> Ash.Query.load([
                 :count_of_recent_popular_comments
               ])
               |> Ash.read_one!()
    end

    test "a count aggregate with a related filter returns the proper value" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title", category: "foo"})
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

      assert %Post{count_of_comments_that_have_a_post: 3} =
               Post
               |> Ash.Query.load([
                 :count_of_comments_that_have_a_post
               ])
               |> Ash.read_one!()
    end

    test "a count aggregate with a related filter that uses `exists` returns the proper value" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title", category: "foo"})
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

      assert %Post{count_of_comments_that_have_a_post_with_exists: 3} =
               Post
               |> Ash.Query.load([
                 :count_of_comments_that_have_a_post_with_exists
               ])
               |> Ash.read_one!()
    end

    test "a count with a filter that references a relationship that also has a filter" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title", category: "foo"})
        |> Ash.create!()

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      comment2 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 10, resource_id: comment.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 1, resource_id: comment2.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      assert %Post{count_of_popular_comments: 1} =
               Post
               |> Ash.Query.load([
                 :count_of_popular_comments
               ])
               |> Ash.read_one!()
    end

    test "a count with a filter that references a to many relationship can be aggregated at the query level" do
      Post
      |> Ash.Query.filter(comments.likes > 10)
      |> Ash.count!()
    end

    test "a list with a filter that references a to many relationship can be aggregated at the query level" do
      Post
      |> Ash.Query.filter(comments.likes > 10)
      |> Ash.list!(:title)
    end

    test "a count with a limit and a filter can be aggregated at the query level" do
      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "foo"})
      |> Ash.create!()

      assert 1 =
               Post
               |> Ash.Query.for_read(:title_is_foo)
               |> Ash.Query.limit(1)
               |> Ash.count!()
    end

    test "a count can filter independently of the query" do
      assert {:ok, %{count: 0, count2: 0}} =
               Post
               |> Ash.aggregate([
                 {:count, :count, query: [filter: Ash.Expr.expr(comments.likes > 10)]},
                 {:count2, :count, query: [filter: Ash.Expr.expr(comments.likes < 10)]}
               ])
    end

    test "multiple aggregates will be grouped up if possible" do
      assert {:ok, %{count: 0, count2: 0}} =
               Post
               |> Ash.aggregate([
                 {:count, :count,
                  query: [
                    filter:
                      Ash.Expr.expr(author.first_name == "fred" and author.last_name == "weasley")
                  ]},
                 {:count2, :count,
                  query: [
                    filter:
                      Ash.Expr.expr(
                        author.first_name == "george" and author.last_name == "weasley"
                      )
                  ]}
               ])
    end

    test "a count with a filter that references a relationship combined with another" do
      post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title", category: "foo"})
        |> Ash.create!()

      comment =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      comment2 =
        Comment
        |> Ash.Changeset.for_create(:create, %{title: "match"})
        |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
        |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 10, resource_id: comment.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      Rating
      |> Ash.Changeset.for_create(:create, %{score: 1, resource_id: comment2.id})
      |> Ash.Changeset.set_context(%{data_layer: %{table: "comment_ratings"}})
      |> Ash.create!()

      assert %Post{count_of_popular_comments: 1} =
               Post
               |> Ash.Query.load([
                 :count_of_comments,
                 :count_of_popular_comments
               ])
               |> Ash.read_one!()
    end
  end

  @tag :regression
  test "filter and aggregate names do not collide with the same names" do
    club = Ash.Seed.seed!(AshPostgres.Test.StandupClub, %{name: "Studio 54"})

    club_comedians =
      Enum.map([1, 2, 3], fn idx ->
        Ash.Seed.seed!(AshPostgres.Test.Comedian, %{
          name: "Bill Burr-#{idx}",
          standup_club_id: club.id
        })
      end)

    Enum.each(club_comedians, fn comedian ->
      Range.new(1, Enum.random([2, 3, 4, 5, 6]))
      |> Enum.each(fn joke_idx ->
        joke =
          Ash.Seed.seed!(AshPostgres.Test.Joke, %{
            comedian_id: comedian.id,
            text: "Haha I am a joke number #{joke_idx}"
          })

        Range.new(1, Enum.random([2, 3, 4, 5, 6]))
        |> Enum.each(fn _idx ->
          Ash.Seed.seed!(AshPostgres.Test.Punchline, %{joke_id: joke.id})
        end)
      end)
    end)

    Range.new(1, Enum.random([2, 3, 4, 5, 6]))
    |> Enum.each(fn joke_idx ->
      joke =
        Ash.Seed.seed!(AshPostgres.Test.Joke, %{
          standup_club_id: club.id,
          text: "Haha I am a club joke number #{joke_idx}"
        })

      Range.new(1, Enum.random([2, 3, 4, 5, 6]))
      |> Enum.each(fn _idx ->
        Ash.Seed.seed!(AshPostgres.Test.Punchline, %{joke_id: joke.id})
      end)
    end)

    filter = %{
      comedians: %{
        jokes: %{
          punchline_count: %{
            greater_than: 0
          }
        }
      }
    }

    Ash.Query.filter_input(AshPostgres.Test.StandupClub, filter)
    |> Ash.read!(load: [:punchline_count])
  end

  @tag :regression
  test "aggregates with modify_query raise an appropriate error" do
    assert_raise Ash.Error.Unknown, ~r/does not currently support aggregates/, fn ->
      Post
      |> Ash.Query.load([
        :count_comments_with_modify_query
      ])
      |> Ash.read_one!()
    end
  end
end
