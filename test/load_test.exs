defmodule AshPostgres.Test.LoadTest do
  use AshPostgres.RepoCase, async: false

  alias AshPostgres.Test.{
    Author,
    Comment,
    Post,
    PostFollower,
    Record,
    StatefulPostFollower,
    TempEntity,
    User
  }

  require Ash.Query

  test "has_many relationships can be loaded" do
    assert %Post{comments: %Ash.NotLoaded{type: :relationship}} =
             post =
             Post
             |> Ash.Changeset.for_create(:create, %{title: "title"})
             |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    results =
      Post
      |> Ash.Query.load(:comments)
      |> Ash.read!()

    assert [%Post{comments: [%{title: "match"}]}] = results
  end

  test "has_one relationships properly limit in the data layer" do
    assert %Post{comments: %Ash.NotLoaded{type: :relationship}} =
             post =
             Post
             |> Ash.Changeset.for_create(:create, %{title: "title"})
             |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
    |> Ash.create!()

    :timer.sleep(1)

    assert %{id: second_comment_id} =
             Comment
             |> Ash.Changeset.for_create(:create, %{title: "match"})
             |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
             |> Ash.create!()

    assert %{id: ^second_comment_id} =
             Post
             |> Ash.Query.load(latest_comment: [:expects_only_one_comment])
             |> Ash.read_one!()
             |> Map.get(:latest_comment)
  end

  test "belongs_to relationships can be loaded" do
    assert %Comment{post: %Ash.NotLoaded{type: :relationship}} =
             comment =
             Comment
             |> Ash.Changeset.for_create(:create, %{})
             |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "match"})
    |> Ash.Changeset.manage_relationship(:comments, [comment], type: :append_and_remove)
    |> Ash.create!()

    results =
      Comment
      |> Ash.Query.load(:post)
      |> Ash.read!()

    assert [%Comment{post: %{title: "match"}}] = results
  end

  test "many_to_many loads work" do
    source_post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "source"})
      |> Ash.create!()

    destination_post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "destination"})
      |> Ash.create!()

    destination_post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "destination"})
      |> Ash.create!()

    source_post
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [destination_post, destination_post2],
      type: :append_and_remove
    )
    |> Ash.update!()

    results =
      source_post
      |> Ash.load!(:linked_posts)

    assert %{linked_posts: [%{title: "destination"}, %{title: "destination"}]} = results
  end

  test "many_to_many loads work with filter on join relationship" do
    followers =
      for i <- 0..2 do
        User
        |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
        |> Ash.create!()
      end

    Post
    |> Ash.Changeset.for_create(:create, %{title: "a"})
    |> Ash.Changeset.manage_relationship(:stateful_followers, followers, type: :append_and_remove)
    |> Ash.create!()

    StatefulPostFollower
    |> Ash.Query.for_read(:read, %{})
    |> Ash.Query.limit(1)
    |> Ash.read_one!()
    |> Ash.Changeset.for_update(:update, %{state: :inactive})
    |> Ash.update!()

    [post] =
      Post
      |> Ash.Query.for_read(:read, %{})
      |> Ash.Query.load(:active_followers)
      |> Ash.read!()

    assert length(post.active_followers) == 2
  end

  test "many_to_many loads work with filter on the join relationship via the parent" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "a"})
      |> Ash.create!()

    for i <- 1..2 do
      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
        |> Ash.create!()

      PostFollower
      |> Ash.Changeset.for_create(:create, %{order: i, post_id: post.id, follower_id: user.id})
      |> Ash.create!()
    end

    [post] =
      Post
      |> Ash.Query.for_read(:read, %{})
      |> Ash.Query.load(:first_3_followers)
      |> Ash.read!()

    assert length(post.first_3_followers) == 2
  end

  test "many_to_many loads work when nested" do
    source_post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "source"})
      |> Ash.create!()

    destination_post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "destination"})
      |> Ash.create!()

    source_post
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [destination_post],
      type: :append_and_remove
    )
    |> Ash.update!()

    destination_post
    |> Ash.Changeset.new()
    |> Ash.Changeset.manage_relationship(:linked_posts, [source_post], type: :append_and_remove)
    |> Ash.update!()

    results =
      source_post
      |> Ash.load!(linked_posts: :linked_posts)

    assert %{linked_posts: [%{title: "destination", linked_posts: [%{title: "source"}]}]} =
             results
  end

  describe "lateral join loads" do
    test "parent references are resolved" do
      post1 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      post2_id = post2.id

      post3 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "no match"})
        |> Ash.create!()

      assert [%{posts_with_matching_title: [%{id: ^post2_id}]}] =
               Post
               |> Ash.Query.load(:posts_with_matching_title)
               |> Ash.Query.filter(id == ^post1.id)
               |> Ash.read!()

      assert [%{posts_with_matching_title: []}] =
               Post
               |> Ash.Query.load(:posts_with_matching_title)
               |> Ash.Query.filter(id == ^post3.id)
               |> Ash.read!()
    end

    test "parent references work when joining for filters" do
      %{id: post1_id} =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "title"})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "no match"})
      |> Ash.create!()

      assert [%{id: ^post1_id}] =
               Post
               |> Ash.Query.filter(posts_with_matching_title.id == ^post2.id)
               |> Ash.read!()
    end

    test "lateral join loads (loads with limits or offsets) are supported" do
      assert %Post{comments: %Ash.NotLoaded{type: :relationship}} =
               post =
               Post
               |> Ash.Changeset.for_create(:create, %{title: "title"})
               |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "abc"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      Comment
      |> Ash.Changeset.for_create(:create, %{title: "def"})
      |> Ash.Changeset.manage_relationship(:post, post, type: :append_and_remove)
      |> Ash.create!()

      comments_query =
        Comment
        |> Ash.Query.limit(1)
        |> Ash.Query.sort(:title)

      results =
        Post
        |> Ash.Query.load(comments: comments_query)
        |> Ash.read!()

      assert [%Post{comments: [%{title: "abc"}]}] = results

      comments_query =
        Comment
        |> Ash.Query.limit(1)
        |> Ash.Query.sort(title: :desc)

      results =
        Post
        |> Ash.Query.load(comments: comments_query)
        |> Ash.read!()

      assert [%Post{comments: [%{title: "def"}]}] = results

      comments_query =
        Comment
        |> Ash.Query.limit(2)
        |> Ash.Query.sort(title: :desc)

      results =
        Post
        |> Ash.Query.load(comments: comments_query)
        |> Ash.read!()

      assert [%Post{comments: [%{title: "def"}, %{title: "abc"}]}] = results
    end

    test "loading many to many relationships on records works without loading its join relationship when using code interface" do
      source_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "source"})
        |> Ash.create!()

      destination_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "abc"})
        |> Ash.create!()

      destination_post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "def"})
        |> Ash.create!()

      source_post
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:linked_posts, [destination_post, destination_post2],
        type: :append_and_remove
      )
      |> Ash.update!()

      assert %{linked_posts: [_, _]} = Post.get_by_id!(source_post.id, load: [:linked_posts])
    end

    test "lateral join loads with many to many relationships are supported" do
      source_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "source"})
        |> Ash.create!()

      destination_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "abc"})
        |> Ash.create!()

      destination_post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "def"})
        |> Ash.create!()

      source_post
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:linked_posts, [destination_post, destination_post2],
        type: :append_and_remove
      )
      |> Ash.update!()

      linked_posts_query =
        Post
        |> Ash.Query.limit(1)
        |> Ash.Query.sort(title: :asc)

      results =
        source_post
        |> Ash.load!(linked_posts: linked_posts_query)

      assert %{linked_posts: [%{title: "abc"}]} = results

      linked_posts_query =
        Post
        |> Ash.Query.limit(2)
        |> Ash.Query.sort(title: :asc)

      results =
        source_post
        |> Ash.load!(linked_posts: linked_posts_query)

      assert %{linked_posts: [%{title: "abc"}, %{title: "def"}]} = results
    end

    test "lateral join loads with many to many relationships are supported with aggregates" do
      source_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "source"})
        |> Ash.create!()

      destination_post =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "abc"})
        |> Ash.create!()

      destination_post2 =
        Post
        |> Ash.Changeset.for_create(:create, %{title: "def"})
        |> Ash.create!()

      source_post
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:linked_posts, [destination_post, destination_post2],
        type: :append_and_remove
      )
      |> Ash.update!()

      linked_posts_query =
        Post
        |> Ash.Query.limit(1)
        |> Ash.Query.sort(title: :asc)

      results =
        source_post
        |> Ash.load!(linked_posts: linked_posts_query)

      assert %{linked_posts: [%{title: "abc"}]} = results

      linked_posts_query =
        Post
        |> Ash.Query.limit(2)
        |> Ash.Query.sort(title: :asc)
        |> Ash.Query.filter(count_of_comments_called_match == 0)

      results =
        source_post
        |> Ash.load!(linked_posts: linked_posts_query)

      assert %{linked_posts: [%{title: "abc"}, %{title: "def"}]} = results
    end

    test "lateral join loads with read action from a custom table and schema" do
      record = Record |> Ash.Changeset.for_create(:create, %{full_name: "name"}) |> Ash.create!()

      temp_entity =
        TempEntity |> Ash.Changeset.for_create(:create, %{full_name: "name"}) |> Ash.create!()

      assert %{entity: entity} = Ash.load!(record, :entity)

      assert temp_entity.id == entity.id
    end
  end

  describe "relationship pagination" do
    test "it allows paginating has_many relationships with offset pagination" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "a"})
        |> Ash.create!()

      author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "b"})
        |> Ash.create!()

      for i <- 0..9 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author1 post#{i}", author_id: author1.id})
        |> Ash.create!()

        Post
        |> Ash.Changeset.for_create(:create, %{title: "author2 post#{i}", author_id: author2.id})
        |> Ash.create!()
      end

      paginated_posts =
        Post
        |> Ash.Query.for_read(:paginated)
        |> Ash.Query.page(limit: 2, offset: 2)
        |> Ash.Query.sort(:title)

      assert [author1, author2] =
               Author
               |> Ash.Query.sort(:first_name)
               |> Ash.Query.load(posts: paginated_posts)
               |> Ash.read!()

      assert %Ash.Page.Offset{
               results: [%{title: "author1 post2"}, %{title: "author1 post3"}]
             } = author1.posts

      assert %Ash.Page.Offset{
               results: [%{title: "author2 post2"}, %{title: "author2 post3"}]
             } = author2.posts

      assert %Ash.Page.Offset{
               results: [%{title: "author1 post4"}, %{title: "author1 post5"}]
             } = Ash.page!(author1.posts, :next)
    end

    test "it allows paginating has_many relationships with keyset pagination" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "a"})
        |> Ash.create!()

      author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "b"})
        |> Ash.create!()

      for i <- 0..9 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author1 post#{i}", author_id: author1.id})
        |> Ash.create!()

        Post
        |> Ash.Changeset.for_create(:create, %{title: "author2 post#{i}", author_id: author2.id})
        |> Ash.create!()
      end

      paginated_posts =
        Post
        |> Ash.Query.for_read(:keyset)
        |> Ash.Query.page(limit: 2)
        |> Ash.Query.sort(:title)

      assert [author1, author2] =
               Author
               |> Ash.Query.sort(:first_name)
               |> Ash.Query.load(posts: paginated_posts)
               |> Ash.read!()

      assert %Ash.Page.Keyset{
               results: [%{title: "author1 post0"}, %{title: "author1 post1"}]
             } = author1.posts

      assert %Ash.Page.Keyset{
               results: [%{title: "author2 post0"}, %{title: "author2 post1"}]
             } = author2.posts

      assert %Ash.Page.Keyset{
               results: [%{title: "author1 post2"}, %{title: "author1 post3"}]
             } = Ash.page!(author1.posts, :next)
    end

    test "it allows paginating many_to_many relationships with offset pagination" do
      followers =
        for i <- 0..9 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
          |> Ash.create!()
        end

      followers_0_to_6 = Enum.take(followers, 6)
      followers_5_to_9 = Enum.slice(followers, 5..9)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "a"})
      |> Ash.Changeset.manage_relationship(:followers, followers_0_to_6, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:followers, followers_5_to_9, type: :append_and_remove)
      |> Ash.create!()

      paginated_followers =
        User
        |> Ash.Query.page(limit: 2)
        |> Ash.Query.sort(:name)

      assert [post1, post2] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.Query.load(followers: paginated_followers)
               |> Ash.read!()

      assert %Ash.Page.Offset{
               results: [%{name: "user0"}, %{name: "user1"}]
             } = post1.followers

      assert %Ash.Page.Offset{
               results: [%{name: "user5"}, %{name: "user6"}]
             } = post2.followers

      assert %Ash.Page.Offset{
               results: [%{name: "user2"}, %{name: "user3"}]
             } = Ash.page!(post1.followers, :next)
    end

    test "it allows paginating many_to_many relationships with keyset pagination" do
      followers =
        for i <- 0..9 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}"})
          |> Ash.create!()
        end

      followers_0_to_6 = Enum.take(followers, 6)
      followers_5_to_9 = Enum.slice(followers, 5..9)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "a"})
      |> Ash.Changeset.manage_relationship(:followers, followers_0_to_6, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:followers, followers_5_to_9, type: :append_and_remove)
      |> Ash.create!()

      paginated_followers =
        User
        |> Ash.Query.for_read(:keyset)
        |> Ash.Query.page(limit: 2)
        |> Ash.Query.sort(:name)

      assert [post1, post2] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.Query.load(followers: paginated_followers)
               |> Ash.read!()

      assert %Ash.Page.Keyset{
               results: [%{name: "user0"}, %{name: "user1"}]
             } = post1.followers

      assert %Ash.Page.Keyset{
               results: [%{name: "user5"}, %{name: "user6"}]
             } = post2.followers

      assert %Ash.Page.Keyset{
               results: [%{name: "user2"}, %{name: "user3"}]
             } = Ash.page!(post1.followers, :next)
    end

    test "it allows paginating calculation ordered many_to_many relationships with offset" do
      followers =
        for i <- 0..9 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
          |> Ash.create!()
        end

      followers_0_to_6_reversed =
        Enum.take(followers, 7)
        |> Enum.with_index()
        |> Enum.map(fn {follower, idx} -> %{id: follower.id, order: 6 - idx} end)

      followers_5_to_9_reversed =
        Enum.slice(followers, 5..9)
        |> Enum.with_index()
        |> Enum.map(fn {follower, idx} -> %{id: follower.id, order: 9 - idx} end)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "a"})
      |> Ash.Changeset.manage_relationship(:followers, followers_0_to_6_reversed,
        on_lookup: {:relate_and_update, :create, :read, [:order]}
      )
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:followers, followers_5_to_9_reversed,
        on_lookup: {:relate_and_update, :create, :read, [:order]}
      )
      |> Ash.create!()

      paginated_sorted_followers =
        User
        |> Ash.Query.page(limit: 2)

      assert [post1, post2] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.Query.load(sorted_followers: paginated_sorted_followers)
               |> Ash.read!()

      assert %Ash.Page.Offset{
               results: [%{name: "user6"}, %{name: "user5"}]
             } = post1.sorted_followers

      assert %Ash.Page.Offset{
               results: [%{name: "user9"}, %{name: "user8"}]
             } = post2.sorted_followers

      assert %Ash.Page.Offset{
               results: [%{name: "user4"}, %{name: "user3"}]
             } = Ash.page!(post1.sorted_followers, :next)
    end

    test "it allows paginating calculation ordered many_to_many relationships with keyset" do
      followers =
        for i <- 0..9 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
          |> Ash.create!()
        end

      followers_0_to_6_reversed =
        Enum.take(followers, 7)
        |> Enum.with_index()
        |> Enum.map(fn {follower, idx} -> %{id: follower.id, order: 6 - idx} end)

      followers_5_to_9_reversed =
        Enum.slice(followers, 5..9)
        |> Enum.with_index()
        |> Enum.map(fn {follower, idx} -> %{id: follower.id, order: 9 - idx} end)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "a"})
      |> Ash.Changeset.manage_relationship(:followers, followers_0_to_6_reversed,
        on_lookup: {:relate_and_update, :create, :read, [:order]}
      )
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:followers, followers_5_to_9_reversed,
        on_lookup: {:relate_and_update, :create, :read, [:order]}
      )
      |> Ash.create!()

      paginated_sorted_followers =
        User
        |> Ash.Query.for_read(:keyset)
        |> Ash.Query.page(limit: 2)

      assert [post1, post2] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.Query.load(sorted_followers: paginated_sorted_followers)
               |> Ash.read!()

      assert %Ash.Page.Keyset{
               results: [%{name: "user6"}, %{name: "user5"}]
             } = post1.sorted_followers

      assert %Ash.Page.Keyset{
               results: [%{name: "user9"}, %{name: "user8"}]
             } = post2.sorted_followers

      assert %Ash.Page.Keyset{
               results: [%{name: "user4"}, %{name: "user3"}]
             } = Ash.page!(post1.sorted_followers, :next)
    end

    test "works when nested with offset" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "a"})
        |> Ash.create!()

      author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "b"})
        |> Ash.create!()

      followers =
        for i <- 0..9 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
          |> Ash.create!()
        end

      followers_0_to_6 = Enum.take(followers, 6)
      followers_5_to_9 = Enum.slice(followers, 5..9)

      for i <- 0..5 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author1 post#{i}", author_id: author1.id})
        |> Ash.Changeset.manage_relationship(:followers, followers_0_to_6,
          type: :append_and_remove
        )
        |> Ash.create!()

        Post
        |> Ash.Changeset.for_create(:create, %{title: "author2 post#{i}", author_id: author2.id})
        |> Ash.Changeset.manage_relationship(:followers, followers_5_to_9,
          type: :append_and_remove
        )
        |> Ash.create!()
      end

      paginated_followers =
        User
        |> Ash.Query.page(limit: 1)
        |> Ash.Query.sort(:name)

      paginated_posts =
        Post
        |> Ash.Query.for_read(:paginated)
        |> Ash.Query.load(followers: paginated_followers)
        |> Ash.Query.page(limit: 1)
        |> Ash.Query.sort(:title)

      assert %Ash.Page.Offset{results: [author1]} =
               Author
               |> Ash.Query.sort(:first_name)
               |> Ash.Query.load(posts: paginated_posts)
               |> Ash.read!(page: [limit: 1])

      assert %Ash.Page.Offset{
               results: [
                 %{
                   title: "author1 post0",
                   followers: %Ash.Page.Offset{results: [%{name: "user0"}]} = followers_page
                 }
               ]
             } = author1.posts

      assert %Ash.Page.Offset{results: [%{title: "author1 post1"}]} =
               Ash.page!(author1.posts, :next)

      assert %Ash.Page.Offset{results: [%{name: "user1"}]} = Ash.page!(followers_page, :next)
    end

    test "works when nested with keyset" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "a"})
        |> Ash.create!()

      author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "b"})
        |> Ash.create!()

      followers =
        for i <- 0..9 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
          |> Ash.create!()
        end

      followers_0_to_6 = Enum.take(followers, 6)
      followers_5_to_9 = Enum.slice(followers, 5..9)

      for i <- 0..5 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author1 post#{i}", author_id: author1.id})
        |> Ash.Changeset.manage_relationship(:followers, followers_0_to_6,
          type: :append_and_remove
        )
        |> Ash.create!()

        Post
        |> Ash.Changeset.for_create(:create, %{title: "author2 post#{i}", author_id: author2.id})
        |> Ash.Changeset.manage_relationship(:followers, followers_5_to_9,
          type: :append_and_remove
        )
        |> Ash.create!()
      end

      paginated_followers =
        User
        |> Ash.Query.for_read(:keyset)
        |> Ash.Query.page(limit: 1)
        |> Ash.Query.sort(:name)

      paginated_posts =
        Post
        |> Ash.Query.for_read(:keyset)
        |> Ash.Query.load(followers: paginated_followers)
        |> Ash.Query.page(limit: 1)
        |> Ash.Query.sort(:title)

      assert [author1, _author2] =
               Author
               |> Ash.Query.sort(:first_name)
               |> Ash.Query.load(posts: paginated_posts)
               |> Ash.read!()

      assert %Ash.Page.Keyset{
               results: [
                 %{
                   title: "author1 post0",
                   followers: %Ash.Page.Keyset{results: [%{name: "user0"}]} = followers_page
                 }
               ]
             } = author1.posts

      assert %Ash.Page.Keyset{results: [%{title: "author1 post1"}]} =
               Ash.page!(author1.posts, :next)

      assert %Ash.Page.Keyset{results: [%{name: "user1"}]} = Ash.page!(followers_page, :next)
    end

    test "it allows counting has_many relationships" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "a"})
        |> Ash.create!()

      author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "b"})
        |> Ash.create!()

      for i <- 1..3 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author1 post#{i}", author_id: author1.id})
        |> Ash.create!()
      end

      for i <- 1..6 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author2 post#{i}", author_id: author2.id})
        |> Ash.create!()
      end

      paginated_posts =
        Post
        |> Ash.Query.for_read(:paginated)
        |> Ash.Query.page(limit: 2, offset: 2, count: true)

      assert [author1, author2] =
               Author
               |> Ash.Query.sort(:first_name)
               |> Ash.Query.load(posts: paginated_posts)
               |> Ash.read!()

      assert %Ash.Page.Offset{count: 3} = author1.posts
      assert %Ash.Page.Offset{count: 6} = author2.posts
    end

    test "it allows counting many_to_many relationships" do
      followers =
        for i <- 1..9 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
          |> Ash.create!()
        end

      followers_1_to_3 = Enum.take(followers, 3)
      followers_4_to_9 = Enum.slice(followers, 3..9)

      Post
      |> Ash.Changeset.for_create(:create, %{title: "a"})
      |> Ash.Changeset.manage_relationship(:followers, followers_1_to_3, type: :append_and_remove)
      |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{title: "b"})
      |> Ash.Changeset.manage_relationship(:followers, followers_4_to_9, type: :append_and_remove)
      |> Ash.create!()

      paginated_followers =
        User
        |> Ash.Query.page(limit: 2, count: true)
        |> Ash.Query.sort(:name)

      assert [post1, post2] =
               Post
               |> Ash.Query.sort(:title)
               |> Ash.Query.load(followers: paginated_followers)
               |> Ash.read!()

      assert %Ash.Page.Offset{count: 3} = post1.followers
      assert %Ash.Page.Offset{count: 6} = post2.followers
    end

    test "allows counting nested relationships" do
      author1 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "a"})
        |> Ash.create!()

      _author2 =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "b"})
        |> Ash.create!()

      followers =
        for i <- 1..3 do
          User
          |> Ash.Changeset.for_create(:create, %{name: "user#{i}", is_active: true})
          |> Ash.create!()
        end

      for i <- 1..5 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author1 post#{i}", author_id: author1.id})
        |> Ash.Changeset.manage_relationship(:followers, followers, type: :append_and_remove)
        |> Ash.create!()
      end

      paginated_followers =
        User
        |> Ash.Query.page(limit: 1, count: true)

      paginated_posts =
        Post
        |> Ash.Query.for_read(:paginated)
        |> Ash.Query.load(followers: paginated_followers)
        |> Ash.Query.page(limit: 1, count: true)

      assert %Ash.Page.Offset{results: [author1], count: 2} =
               Author
               |> Ash.Query.sort(:first_name)
               |> Ash.Query.load(posts: paginated_posts)
               |> Ash.read!(page: [limit: 1, count: true])

      assert %Ash.Page.Offset{} = page = author1.posts
      assert [result] = page.results
      assert %Ash.Page.Offset{} = nested_page = result.followers
      assert length(nested_page.results) == 1
      assert nested_page.count == 3
    end

    test "doesn't leak the internal count aggregate when counting" do
      author =
        Author
        |> Ash.Changeset.for_create(:create, %{first_name: "a"})
        |> Ash.create!()

      for i <- 1..3 do
        Post
        |> Ash.Changeset.for_create(:create, %{title: "author1 post#{i}", author_id: author.id})
        |> Ash.create!()
      end

      paginated_posts =
        Post
        |> Ash.Query.for_read(:paginated)
        |> Ash.Query.page(limit: 2, offset: 2, count: true)

      assert [author] =
               Author
               |> Ash.Query.load(posts: paginated_posts)
               |> Ash.read!()

      assert %Ash.Page.Offset{count: 3} = author.posts
      assert %{} == author.aggregates
    end
  end
end
