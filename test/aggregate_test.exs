# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshSql.AggregateTest do
  use AshPostgres.RepoCase, async: false
  import ExUnit.CaptureIO
  alias AshPostgres.Test.{Author, Chat, Comment, Organization, Post, Rating, User}

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

    test "aggregates with bypass can count across all tenants in context multitenancy" do
      [org1, org2] =
        for i <- 1..2 do
          Org
          |> Ash.Changeset.for_create(:create, %{name: "Org#{i}"})
          |> Ash.create!()
        end

      [user1, user2] =
        for {org, i} <- Enum.with_index([org1, org2], 1) do
          User
          |> Ash.Changeset.for_create(:create, %{name: "User#{i}", org_id: org.id})
          |> Ash.create!()
        end

      for i <- 1..2 do
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post #{i} in Org1", user_id: user1.id})
        |> Ash.create!(tenant: "org_#{org1.id}")
      end

      for i <- 1..3 do
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post #{i} in Org2", user_id: user1.id})
        |> Ash.create!(tenant: "org_#{org2.id}")
      end

      # Test: Load user1 with bypass aggregates from org1 context
      loaded_user1 =
        Ash.load!(
          user1,
          [:posts_count_all_tenants, :posts_count_current_tenant],
          tenant: "org_#{org1.id}"
        )

      # Bypass sees user1's posts from ALL tenant schemas (2 in org1 + 3 in org2 = 5)
      assert loaded_user1.posts_count_all_tenants == 5
      # Non-bypass sees only user1's posts in org1 schema (2)
      assert loaded_user1.posts_count_current_tenant == 2

      # Test: Load user2 (who has no posts) with bypass aggregates from org2 context
      loaded_user2 =
        Ash.load!(
          user2,
          [:posts_count_all_tenants, :posts_count_current_tenant],
          tenant: "org_#{org2.id}"
        )

      # User2 has no posts, so both aggregates return 0
      assert loaded_user2.posts_count_all_tenants == 0
      # Non-bypass also sees 0 for user2
      assert loaded_user2.posts_count_current_tenant == 0
    end

    test "bypass aggregates work with list and exists for context multitenancy" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org1"})
        |> Ash.create!()

      org2 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org2"})
        |> Ash.create!()

      user1 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "User1", org_id: org1.id})
        |> Ash.create!()

      _user2 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "User2", org_id: org2.id})
        |> Ash.create!()

      # Create posts with distinct names in different tenant schemas
      # User1 has posts in BOTH tenants to demonstrate bypass vs non-bypass
      Post
      |> Ash.Changeset.for_create(:create, %{name: "Alpha", user_id: user1.id})
      |> Ash.create!(tenant: "org_#{org1.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{name: "Beta", user_id: user1.id})
      |> Ash.create!(tenant: "org_#{org1.id}")

      # User1 also has a post in org2 - this demonstrates bypass aggregates
      Post
      |> Ash.Changeset.for_create(:create, %{name: "Gamma", user_id: user1.id})
      |> Ash.create!(tenant: "org_#{org2.id}")

      # Test LIST aggregate with bypass
      loaded_user1 =
        Ash.load!(
          user1,
          [:post_names_all_tenants, :post_names_current_tenant],
          tenant: "org_#{org1.id}"
        )

      # Bypass should see all post names across all tenants
      assert Enum.sort(loaded_user1.post_names_all_tenants) == ["Alpha", "Beta", "Gamma"]
      # Non-bypass should see only org1 posts
      assert Enum.sort(loaded_user1.post_names_current_tenant) == ["Alpha", "Beta"]

      # Test EXISTS aggregate with bypass
      loaded_user1_exists =
        Ash.load!(
          user1,
          [:has_posts_all_tenants, :has_posts_current_tenant],
          tenant: "org_#{org1.id}"
        )

      assert loaded_user1_exists.has_posts_all_tenants == true
      assert loaded_user1_exists.has_posts_current_tenant == true

      # Create a user with no posts at all
      user3 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "User3", org_id: org1.id})
        |> Ash.create!()

      loaded_user3 =
        Ash.load!(
          user3,
          [:has_posts_all_tenants, :has_posts_current_tenant],
          tenant: "org_#{org1.id}"
        )

      # Bypass still respects relationship filter - user3 has no posts in any tenant
      assert loaded_user3.has_posts_all_tenants == false
      # Non-bypass also sees no posts for this user in current tenant
      assert loaded_user3.has_posts_current_tenant == false
    end

    test "bypass aggregates work with linked resources in context multitenancy" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org1"})
        |> Ash.create!()

      org2 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org2"})
        |> Ash.create!()

      post1_org1 =
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post 1 Org1"})
        |> Ash.create!(tenant: "org_#{org1.id}")

      post2_org1 =
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post 2 Org1"})
        |> Ash.create!(tenant: "org_#{org1.id}")

      post1_org2 =
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post 1 Org2"})
        |> Ash.create!(tenant: "org_#{org2.id}")

      post2_org2 =
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post 2 Org2"})
        |> Ash.create!(tenant: "org_#{org2.id}")

      # Link post1_org1 to post2_org1 (same tenant)
      post1_org1
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:linked_posts, [post2_org1], type: :append_and_remove)
      |> Ash.update!(tenant: "org_#{org1.id}")

      # Link post1_org2 to both post2_org2 and post1_org1 (cross-tenant link)
      post1_org2
      |> Ash.Changeset.new()
      |> Ash.Changeset.manage_relationship(:linked_posts, [post2_org2], type: :append_and_remove)
      |> Ash.update!(tenant: "org_#{org2.id}")

      # Test aggregates on linked posts
      loaded_post1_org1 =
        Ash.load!(
          post1_org1,
          [:total_linked_posts_all_tenants, :total_linked_posts_current_tenant],
          tenant: "org_#{org1.id}"
        )

      # Bypass should see linked posts across all tenants
      # Note: The actual count depends on how cross-tenant links are stored
      assert loaded_post1_org1.total_linked_posts_current_tenant == 1
      # Bypass may see more depending on implementation
      assert loaded_post1_org1.total_linked_posts_all_tenants >= 1
    end

    test "bypass aggregates with no data return correct empty values in context multitenancy" do
      org =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "EmptyOrg"})
        |> Ash.create!()

      user =
        User
        |> Ash.Changeset.for_create(:create, %{name: "UserNoPost", org_id: org.id})
        |> Ash.create!()

      # Load all aggregate types with no posts
      loaded_user =
        Ash.load!(
          user,
          [
            :posts_count_all_tenants,
            :posts_count_current_tenant,
            :post_names_all_tenants,
            :post_names_current_tenant,
            :has_posts_all_tenants,
            :has_posts_current_tenant
          ],
          tenant: "org_#{org.id}"
        )

      # Verify default/empty values
      assert loaded_user.posts_count_all_tenants == 0
      assert loaded_user.posts_count_current_tenant == 0
      assert loaded_user.post_names_all_tenants == []
      assert loaded_user.post_names_current_tenant == []
      # Bypass EXISTS properly returns false when there are no posts across all tenants
      assert loaded_user.has_posts_all_tenants == false
      assert loaded_user.has_posts_current_tenant == false
    end

    test "bypass aggregates work with Ash.aggregate/3 in context multitenancy" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org1"})
        |> Ash.create!()

      org2 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org2"})
        |> Ash.create!()

      # Create posts in different tenants
      for _i <- 1..2 do
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post Org1"})
        |> Ash.create!(tenant: "org_#{org1.id}")
      end

      for _i <- 1..3 do
        Post
        |> Ash.Changeset.for_create(:create, %{name: "Post Org2"})
        |> Ash.create!(tenant: "org_#{org2.id}")
      end

      # Test Ash.aggregate with bypass from org1 context
      result_all =
        Ash.aggregate!(
          Post,
          {:count_all_posts, :count, multitenancy: :bypass},
          tenant: "org_#{org1.id}"
        )

      assert result_all.count_all_posts == 5

      # Test Ash.aggregate without bypass from org1 context
      result_current =
        Ash.aggregate!(
          Post,
          {:count_current_posts, :count},
          tenant: "org_#{org1.id}"
        )

      assert result_current.count_current_posts == 2
    end

    test "bypass aggregates work with multiple different relationships" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "MultiRelOrg1"})
        |> Ash.create!()

      org2 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "MultiRelOrg2"})
        |> Ash.create!()

      user1_org1 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Alice", org_id: org1.id})
        |> Ash.create!()

      user2_org1 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Bob", org_id: org1.id})
        |> Ash.create!()

      user1_org2 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "Charlie", org_id: org2.id})
        |> Ash.create!()

      # Create posts in both orgs (with org_id set for relationship filtering)
      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post 1 Org1",
        user_id: user1_org1.id,
        org_id: org1.id
      })
      |> Ash.create!(tenant: "org_#{org1.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post 2 Org1",
        user_id: user2_org1.id,
        org_id: org1.id
      })
      |> Ash.create!(tenant: "org_#{org1.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post 3 Org1",
        user_id: user1_org1.id,
        org_id: org1.id
      })
      |> Ash.create!(tenant: "org_#{org1.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post 1 Org2",
        user_id: user1_org2.id,
        org_id: org2.id
      })
      |> Ash.create!(tenant: "org_#{org2.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post 2 Org2",
        user_id: user1_org2.id,
        org_id: org2.id
      })
      |> Ash.create!(tenant: "org_#{org2.id}")

      # Create CROSS-TENANT posts: posts in org2's schema that belong to org1
      # This demonstrates the bypass aggregate properly
      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post 4 Org1 CrossTenant",
        user_id: user1_org1.id,
        org_id: org1.id
      })
      |> Ash.create!(tenant: "org_#{org2.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post 5 Org1 CrossTenant",
        user_id: user2_org1.id,
        org_id: org1.id
      })
      |> Ash.create!(tenant: "org_#{org2.id}")

      # Load org1 with aggregates for BOTH posts (context multitenancy) and users (attribute multitenancy)
      loaded_org1 =
        Ash.load!(
          org1,
          [
            :posts_count_all_tenants,
            :posts_count_current_tenant,
            :users_count,
            :post_names_all_tenants,
            :post_names_current_tenant,
            :user_names,
            :has_posts_all_tenants
          ],
          tenant: "org_#{org1.id}"
        )

      # Test POSTS aggregates with bypass (context-based multitenancy)
      # Bypass should see org1's posts across ALL tenants (3 in org1 + 2 in org2 = 5 total)
      assert loaded_org1.posts_count_all_tenants == 5
      # Non-bypass should see only org1 posts in CURRENT tenant (3)
      assert loaded_org1.posts_count_current_tenant == 3

      # Test POSTS list aggregates
      assert Enum.sort(loaded_org1.post_names_all_tenants) == [
               "Post 1 Org1",
               "Post 2 Org1",
               "Post 3 Org1",
               "Post 4 Org1 CrossTenant",
               "Post 5 Org1 CrossTenant"
             ]

      assert Enum.sort(loaded_org1.post_names_current_tenant) == [
               "Post 1 Org1",
               "Post 2 Org1",
               "Post 3 Org1"
             ]

      # Test USERS aggregates (attribute-based multitenancy - no bypass needed)
      # Users are in public.users table, filtered by org_id = org1.id
      assert loaded_org1.users_count == 2
      assert Enum.sort(loaded_org1.user_names) == ["Alice", "Bob"]

      # Test EXISTS aggregates
      assert loaded_org1.has_posts_all_tenants == true

      # Load org2 and verify it sees different data
      loaded_org2 =
        Ash.load!(
          org2,
          [
            :posts_count_all_tenants,
            :posts_count_current_tenant,
            :users_count
          ],
          tenant: "org_#{org2.id}"
        )

      # Org2 bypass counts its OWN posts across all tenants (respects relationship filter)
      # Org2 has 2 posts with org_id = org2.id (both in org2's schema)
      # Plus the 2 cross-tenant org1 posts are also in org2's schema, but they have org_id = org1.id
      # So bypass still only counts 2 (respects the relationship WHERE org_id = org2.id)
      assert loaded_org2.posts_count_all_tenants == 2
      assert loaded_org2.users_count == 1
      # Non-bypass should see only org2 data in current tenant
      # Posts: 2 org2 posts + 2 cross-tenant org1 posts = 4 posts in org2's schema
      # But filtered by org_id = org2.id = 2 posts
      assert loaded_org2.posts_count_current_tenant == 2
    end

    test "bypass aggregates work with sum, avg, max, min for context multitenancy" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org1"})
        |> Ash.create!()

      org2 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org2"})
        |> Ash.create!()

      user1 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "User1", org_id: org1.id})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post A",
        score: 15,
        rating: Decimal.new("3.5"),
        user_id: user1.id
      })
      |> Ash.create!(tenant: "org_#{org1.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post B",
        score: 20,
        rating: Decimal.new("4.0"),
        user_id: user1.id
      })
      |> Ash.create!(tenant: "org_#{org1.id}")

      # Create posts in org2 tenant with different scores (including a lower min)
      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post C",
        score: 5,
        rating: Decimal.new("4.5"),
        user_id: user1.id
      })
      |> Ash.create!(tenant: "org_#{org2.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Post D",
        score: 40,
        rating: Decimal.new("5.0"),
        user_id: user1.id
      })
      |> Ash.create!(tenant: "org_#{org2.id}")

      # Load user1 with numeric aggregates from org1 context
      loaded_user =
        Ash.load!(
          user1,
          [
            :total_score_all_tenants,
            :total_score_current_tenant,
            :avg_score_all_tenants,
            :avg_score_current_tenant,
            :max_score_all_tenants,
            :max_score_current_tenant,
            :min_score_all_tenants,
            :min_score_current_tenant
          ],
          tenant: "org_#{org1.id}"
        )

      # SUM: Bypass sums across all tenants (15 + 20 + 5 + 40 = 80)
      assert loaded_user.total_score_all_tenants == 80
      # Non-bypass sums only org1 tenant (15 + 20 = 35)
      assert loaded_user.total_score_current_tenant == 35

      # AVG: Bypass averages across all tenants ((15 + 20 + 5 + 40) / 4 = 20.0)
      assert loaded_user.avg_score_all_tenants == 20.0
      # Non-bypass averages only org1 tenant ((15 + 20) / 2 = 17.5)
      assert loaded_user.avg_score_current_tenant == 17.5

      # MAX: Bypass finds max across all tenants (40)
      assert loaded_user.max_score_all_tenants == 40
      # Non-bypass finds max only in org1 tenant (20)
      assert loaded_user.max_score_current_tenant == 20

      # MIN: Bypass finds min across all tenants (5 from org2)
      assert loaded_user.min_score_all_tenants == 5
      # Non-bypass finds min only in org1 tenant (15)
      assert loaded_user.min_score_current_tenant == 15
    end

    test "bypass aggregates work with first for context multitenancy" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org1"})
        |> Ash.create!()

      org2 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org2"})
        |> Ash.create!()

      user1 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "User1", org_id: org1.id})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "First Post",
        score: 100,
        user_id: user1.id
      })
      |> Ash.create!(tenant: "org_#{org2.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{
        name: "Second Post",
        score: 200,
        user_id: user1.id
      })
      |> Ash.create!(tenant: "org_#{org1.id}")

      # Load user1 with first aggregates from org1 context
      loaded_user =
        Ash.load!(
          user1,
          [:first_post_name_all_tenants, :first_post_name_current_tenant],
          tenant: "org_#{org1.id}"
        )

      # Bypass should get first post across all tenants
      # The first aggregate returns the first value it finds
      assert loaded_user.first_post_name_all_tenants in ["First Post", "Second Post"]

      # Non-bypass should get first post only from current tenant
      assert loaded_user.first_post_name_current_tenant == "Second Post"
    end

    test "bypass aggregates return correct nil/empty values with no data" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org1"})
        |> Ash.create!()

      user_no_posts =
        User
        |> Ash.Changeset.for_create(:create, %{name: "UserNoData", org_id: org1.id})
        |> Ash.create!()

      # Load user with no posts (both bypass and non-bypass aggregates)
      loaded_user =
        Ash.load!(
          user_no_posts,
          [
            :total_score_all_tenants,
            :total_score_current_tenant,
            :avg_score_all_tenants,
            :avg_score_current_tenant,
            :max_score_all_tenants,
            :max_score_current_tenant,
            :min_score_all_tenants,
            :min_score_current_tenant,
            :first_post_name_all_tenants,
            :first_post_name_current_tenant
          ],
          tenant: "org_#{org1.id}"
        )

      # Bypass aggregates (all tenants) should return nil when no data
      assert loaded_user.total_score_all_tenants == nil
      assert loaded_user.avg_score_all_tenants == nil
      assert loaded_user.max_score_all_tenants == nil
      assert loaded_user.min_score_all_tenants == nil
      assert loaded_user.first_post_name_all_tenants == nil

      # Non-bypass aggregates (current tenant) should also return nil when no data
      assert loaded_user.total_score_current_tenant == nil
      assert loaded_user.avg_score_current_tenant == nil
      assert loaded_user.max_score_current_tenant == nil
      assert loaded_user.min_score_current_tenant == nil
      assert loaded_user.first_post_name_current_tenant == nil
    end

    test "bypass aggregates work with predefined aggregates for sum, max, min, avg" do
      org1 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org1"})
        |> Ash.create!()

      org2 =
        Org
        |> Ash.Changeset.for_create(:create, %{name: "Org2"})
        |> Ash.create!()

      user1 =
        User
        |> Ash.Changeset.for_create(:create, %{name: "User1", org_id: org1.id})
        |> Ash.create!()

      Post
      |> Ash.Changeset.for_create(:create, %{name: "P1", score: 15, user_id: user1.id})
      |> Ash.create!(tenant: "org_#{org1.id}")

      Post
      |> Ash.Changeset.for_create(:create, %{name: "P2", score: 25, user_id: user1.id})
      |> Ash.create!(tenant: "org_#{org2.id}")

      # Test loading predefined bypass aggregates
      loaded_user =
        user1
        |> Ash.load!(
          [
            :total_score_all_tenants,
            :avg_score_all_tenants,
            :max_score_all_tenants,
            :min_score_all_tenants
          ],
          tenant: "org_#{org1.id}"
        )

      assert loaded_user.total_score_all_tenants == 40
      assert loaded_user.avg_score_all_tenants == 20.0
      assert loaded_user.max_score_all_tenants == 25
      assert loaded_user.min_score_all_tenants == 15
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
    # This used to raise an error, but now should only emit a warning and allow the module to compile
    {_, io} =
      with_io(:stderr, fn ->
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
      end)

    assert io =~ "Aggregate not supported"
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

  @tag :regression
  test "count is accurate" do
    org =
      AshPostgres.Test.Organization
      |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
      |> Ash.create!()

    user =
      AshPostgres.Test.User
      |> Ash.Changeset.for_create(:create, %{name: "test_user", organization_id: org.id})
      |> Ash.create!()

    AshPostgres.Test.User
    |> Ash.Changeset.for_create(:create, %{name: "another_user", organization_id: org.id})
    |> Ash.create!()

    author =
      AshPostgres.Test.Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Test", last_name: "Author"})
      |> Ash.create!()

    post =
      AshPostgres.Test.Post
      |> Ash.Changeset.for_create(:create, %{
        title: "Test Post",
        organization_id: org.id,
        author_id: author.id
      })
      |> Ash.create!()

    AshPostgres.Test.Comment
    |> Ash.Changeset.for_create(:create, %{
      title: "First comment",
      post_id: post.id,
      author_id: author.id
    })
    |> Ash.create!()

    loaded_post =
      AshPostgres.Test.Post
      |> Ash.Query.filter(id == ^post.id)
      |> Ash.Query.load(:count_of_comments)
      |> Ash.read_one!(actor: user)

    assert loaded_post.count_of_comments == 1
  end

  test "aggregate with sort and limit is accurate" do
    # Setup: Create an author with multiple posts
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "John", last_name: "Doe"})
      |> Ash.create!()

    # Create posts with different titles to test sorting
    post1 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "A First Post"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Z Last Post"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    post3 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "M Middle Post"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    # Add comments to posts
    Comment
    |> Ash.Changeset.for_create(:create, %{title: "Comment 1"})
    |> Ash.Changeset.manage_relationship(:post, post1, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "Comment 2"})
    |> Ash.Changeset.manage_relationship(:post, post1, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "Comment 3"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "Comment 4"})
    |> Ash.Changeset.manage_relationship(:post, post3, type: :append_and_remove)
    |> Ash.create!()

    # Query with aggregate, sort, and limit
    # This should ideally use a subquery to apply sort/limit before loading the aggregate
    results =
      Post
      |> Ash.Query.load(:count_of_comments)
      |> Ash.Query.sort(:title)
      |> Ash.Query.limit(2)
      |> Ash.read!()

    # Verify we got the right posts (sorted by title, limited to 2)
    assert length(results) == 2
    assert Enum.at(results, 0).title == "A First Post"
    assert Enum.at(results, 1).title == "M Middle Post"

    # Verify the aggregates are correct
    assert Enum.at(results, 0).count_of_comments == 2
    assert Enum.at(results, 1).count_of_comments == 1
  end

  test "aggregate with sort by aggregate value and limit is accurate" do
    # This tests sorting by the aggregate itself, not by another field
    author =
      Author
      |> Ash.Changeset.for_create(:create, %{first_name: "Jane", last_name: "Smith"})
      |> Ash.create!()

    # Create posts with different numbers of comments
    post1 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post with 3 comments"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    post2 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post with 1 comment"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    post3 =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "Post with 2 comments"})
      |> Ash.Changeset.manage_relationship(:author, author, type: :append_and_remove)
      |> Ash.create!()

    # Add varying numbers of comments
    for _i <- 1..3 do
      Comment
      |> Ash.Changeset.for_create(:create, %{title: "Comment on post 1"})
      |> Ash.Changeset.manage_relationship(:post, post1, type: :append_and_remove)
      |> Ash.create!()
    end

    Comment
    |> Ash.Changeset.for_create(:create, %{title: "Comment on post 2"})
    |> Ash.Changeset.manage_relationship(:post, post2, type: :append_and_remove)
    |> Ash.create!()

    for _i <- 1..2 do
      Comment
      |> Ash.Changeset.for_create(:create, %{title: "Comment on post 3"})
      |> Ash.Changeset.manage_relationship(:post, post3, type: :append_and_remove)
      |> Ash.create!()
    end

    # Query sorting by the aggregate value itself
    results =
      Post
      |> Ash.Query.load(:count_of_comments)
      |> Ash.Query.sort(count_of_comments: :desc)
      |> Ash.Query.limit(2)
      |> Ash.read!()

    # Should get the posts with most comments first
    assert length(results) == 2
    assert Enum.at(results, 0).count_of_comments == 3
    assert Enum.at(results, 1).count_of_comments == 2
  end

  describe "aggregate with parent filter and limited select" do
    test "FAILS when combining select() + limit() with aggregate using parent() in filter" do
      # BUG: When using select() + limit() with an aggregate that uses parent()
      # in its filter, the query generation creates a subquery that's missing the parent
      # fields, causing a SQL error.
      #
      # This bug was found in ash_graphql where GraphQL list queries with pagination
      # would fail when loading aggregates that use parent() in filters.
      #
      # The bug requires BOTH conditions:
      # 1. select() limits which fields are included (e.g., only :id)
      # 2. limit() causes a subquery to be generated
      # 3. An aggregate filter references parent() fields that aren't in select()
      #
      # Without BOTH select() and limit(), the query works fine (see tests below).
      #
      # Current error:
      # ERROR 42703 (undefined_column) column s0.last_read_message_id does not exist
      #
      # Generated query:
      # SELECT s0."id", coalesce(s1."unread_message_count"::bigint, ...)
      # FROM (SELECT sc0."id" AS "id" FROM "chats" AS sc0 LIMIT 10) AS s0
      # LEFT OUTER JOIN LATERAL (
      #   SELECT ... FROM "messages" WHERE ... s0."last_read_message_id" ...  # <- field not in subquery!
      # ) AS s1 ON TRUE
      #
      # Expected fix: Ash should automatically include parent() referenced fields
      # (like last_read_message_id) in the subquery even if not explicitly selected.

      Chat
      |> Ash.Query.select(:id)
      |> Ash.Query.load(:unread_message_count)
      |> Ash.Query.limit(10)
      |> Ash.read!()
    end

    test "works WITHOUT select() - limit alone doesn't cause the bug" do
      Chat
      |> Ash.Query.load(:unread_message_count)
      |> Ash.Query.limit(10)
      |> Ash.read!()
    end

    test "works WITHOUT limit() - select alone doesn't cause the bug" do
      Chat
      |> Ash.Query.select(:id)
      |> Ash.Query.load(:unread_message_count)
      |> Ash.read!()
    end

    test "works when selecting the parent() referenced field explicitly (workaround)" do
      Chat
      |> Ash.Query.select([:id, :last_read_message_id])
      |> Ash.Query.load(:unread_message_count)
      |> Ash.Query.limit(10)
      |> Ash.read!()
    end
  end
end
