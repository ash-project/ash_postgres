defmodule AshPostgres.Test.UnrelatedAggregatesTest do
  @moduledoc false
  use AshPostgres.RepoCase, async: false

  require Ash.Query
  import Ash.Expr

  alias AshPostgres.Test.UnrelatedAggregatesTest.{Profile, Report, SecureProfile, User}

  describe "basic unrelated aggregate definitions" do
    test "aggregates are properly defined with related?: false" do
      aggregates = Ash.Resource.Info.aggregates(User)

      count_agg = Enum.find(aggregates, &(&1.name == :matching_name_profiles_count))
      assert count_agg
      assert count_agg.related? == false
      assert count_agg.resource == Profile
      assert count_agg.kind == :count
      assert count_agg.relationship_path == []

      first_agg = Enum.find(aggregates, &(&1.name == :latest_authored_report))
      assert first_agg
      assert first_agg.related? == false
      assert first_agg.resource == Report
      assert first_agg.kind == :first
      assert first_agg.field == :title

      sum_agg = Enum.find(aggregates, &(&1.name == :total_report_score))
      assert sum_agg
      assert sum_agg.related? == false
      assert sum_agg.resource == Report
      assert sum_agg.kind == :sum
      assert sum_agg.field == :score
    end

    test "unrelated aggregates support all aggregate kinds" do
      aggregates = Ash.Resource.Info.aggregates(User)
      aggregate_names = Enum.map(aggregates, & &1.name)

      # Verify all kinds are supported
      # count
      assert :matching_name_profiles_count in aggregate_names
      # first
      assert :latest_authored_report in aggregate_names
      # sum
      assert :total_report_score in aggregate_names
      # exists
      assert :has_matching_name_profile in aggregate_names
      # list
      assert :matching_profile_names in aggregate_names
      # max
      assert :max_age_same_name in aggregate_names
      # min
      assert :min_age_same_name in aggregate_names
      # avg
      assert :avg_age_same_name in aggregate_names
    end

    test "can define aggregates without parent filters" do
      aggregates = Ash.Resource.Info.aggregates(User)
      total_active_agg = Enum.find(aggregates, &(&1.name == :total_active_profiles))

      assert total_active_agg
      assert total_active_agg.related? == false
      assert total_active_agg.resource == Profile
      # Should have filter but no parent() reference
    end
  end

  describe "loading unrelated aggregates" do
    setup do
      # Create test data
      {:ok, user1} = Ash.create(User, %{name: "John", email: "john@example.com"})
      {:ok, user2} = Ash.create(User, %{name: "Jane", email: "jane@example.com"})

      {:ok, _profile1} = Ash.create(Profile, %{name: "John", age: 25, active: true})
      {:ok, _profile2} = Ash.create(Profile, %{name: "John", age: 30, active: true})
      {:ok, _profile3} = Ash.create(Profile, %{name: "Jane", age: 28, active: true})
      {:ok, _profile4} = Ash.create(Profile, %{name: "Bob", age: 35, active: false})

      base_time = ~U[2024-01-01 12:00:00Z]

      {:ok, _report1} =
        Ash.create(Report, %{
          title: "John's First Report",
          author_name: "John",
          score: 85,
          inserted_at: base_time
        })

      {:ok, _report2} =
        Ash.create(Report, %{
          title: "John's Latest Report",
          author_name: "John",
          score: 92,
          inserted_at: DateTime.add(base_time, 3600, :second)
        })

      {:ok, _report3} =
        Ash.create(Report, %{
          title: "Jane's Report",
          author_name: "Jane",
          score: 78
        })

      %{user1: user1, user2: user2}
    end

    test "can load count unrelated aggregates", %{user1: user1, user2: user2} do
      # Load users with aggregates
      users =
        User
        |> Ash.Query.load([:matching_name_profiles_count, :total_active_profiles])
        |> Ash.read!()

      john = Enum.find(users, &(&1.id == user1.id))
      jane = Enum.find(users, &(&1.id == user2.id))

      # John should have 2 matching profiles
      assert john.matching_name_profiles_count == 2
      # Both should see 3 total active profiles (John x2, Jane x1)
      assert john.total_active_profiles == 3

      # Jane should have 1 matching profile
      assert jane.matching_name_profiles_count == 1
      assert jane.total_active_profiles == 3
    end

    test "can load first unrelated aggregates", %{user1: user1} do
      user =
        User
        |> Ash.Query.filter(id == ^user1.id)
        |> Ash.Query.load(:latest_authored_report)
        |> Ash.read_one!()

      # Should get the latest report title
      assert user.latest_authored_report == "John's Latest Report"
    end

    test "can load sum unrelated aggregates", %{user1: user1, user2: user2} do
      users =
        User
        |> Ash.Query.load(:total_report_score)
        |> Ash.read!()

      john = Enum.find(users, &(&1.id == user1.id))
      jane = Enum.find(users, &(&1.id == user2.id))

      # John's total score: 85 + 92 = 177
      assert john.total_report_score == 177
      # Jane's total score: 78
      assert jane.total_report_score == 78
    end

    test "can load exists unrelated aggregates", %{user1: user1} do
      user =
        User
        |> Ash.Query.filter(id == ^user1.id)
        |> Ash.Query.load(:has_matching_name_profile)
        |> Ash.read_one!()

      assert user.has_matching_name_profile == true
    end

    test "can load list unrelated aggregates", %{user1: user1} do
      user =
        User
        |> Ash.Query.filter(id == ^user1.id)
        |> Ash.Query.load(:matching_profile_names)
        |> Ash.read_one!()

      # Should have two "John" entries
      assert length(user.matching_profile_names) == 2
      assert Enum.all?(user.matching_profile_names, &(&1 == "John"))
    end

    test "can load min/max/avg unrelated aggregates", %{user1: user1} do
      user =
        User
        |> Ash.Query.filter(id == ^user1.id)
        |> Ash.Query.load([:min_age_same_name, :max_age_same_name, :avg_age_same_name])
        |> Ash.read_one!()

      # John profiles have ages 25 and 30
      assert user.min_age_same_name == 25
      assert user.max_age_same_name == 30
      assert user.avg_age_same_name == 27.5
    end
  end

  describe "unrelated aggregates in calculations" do
    setup do
      {:ok, user} = Ash.create(User, %{name: "Alice", email: "alice@example.com"})
      {:ok, _profile} = Ash.create(Profile, %{name: "Alice", age: 25, active: true})

      {:ok, _report} =
        Ash.create(Report, %{
          title: "Alice's Research",
          author_name: "Alice",
          score: 95,
          inserted_at: ~U[2024-01-01 12:00:00Z]
        })

      %{user: user}
    end

    test "calculations using named unrelated aggregates work", %{user: user} do
      user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.load(:matching_profiles_summary)
        |> Ash.read_one!()

      assert user.matching_profiles_summary == "Found 1 profiles"
    end

    test "inline unrelated aggregates in calculations work", %{user: user} do
      user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.load([
          :inline_profile_count,
          :inline_latest_report_title,
          :inline_total_score
        ])
        |> Ash.read_one!()

      assert user.inline_profile_count == 1
      assert user.inline_latest_report_title == "Alice's Research"
      assert user.inline_total_score == 95
    end

    test "complex calculations with multiple inline unrelated aggregates work", %{user: user} do
      user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.load(:complex_calculation)
        |> Ash.read_one!()

      assert user.complex_calculation == %{
               profile_count: 1,
               latest_report: "Alice's Research",
               total_score: 95
             }
    end
  end

  describe "data layer capability checking" do
    test "Postgres data layer should support unrelated aggregates" do
      # This will fail until we implement the capability
      assert AshPostgres.DataLayer.can?(nil, {:aggregate, :unrelated}) == true
    end

    test "error when data layer doesn't support unrelated aggregates" do
      # Test with a mock data layer that doesn't support unrelated aggregates
      # This will be relevant when we add the capability checking
    end
  end

  describe "authorization with unrelated aggregates" do
    # These tests verify that authorization works properly for unrelated aggregates
    # The main concern is that unrelated aggregates don't have relationship paths,
    # so the authorization logic must handle this correctly

    test "unrelated aggregates work without relationship path authorization errors" do
      # This test verifies that unrelated aggregates don't trigger the
      # :lists.droplast([]) error that was happening before the fix
      {:ok, user} = Ash.create(User, %{name: "AuthTest", email: "auth@example.com"})
      {:ok, _profile} = Ash.create(Profile, %{name: "AuthTest", age: 25, active: true})

      # This should not raise authorization errors
      user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.load(:matching_name_profiles_count)
        |> Ash.read_one!()

      assert user.matching_name_profiles_count == 1
    end

    test "unrelated aggregates in calculations don't cause authorization errors" do
      # Test that the authorization logic correctly handles unrelated aggregates
      # when they're referenced in calculations
      {:ok, user} = Ash.create(User, %{name: "CalcAuth", email: "calcauth@example.com"})
      {:ok, _profile} = Ash.create(Profile, %{name: "CalcAuth", age: 30, active: true})

      # This should not raise authorization errors
      user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.load(:matching_profiles_summary)
        |> Ash.read_one!()

      assert user.matching_profiles_summary == "Found 1 profiles"
    end

    test "multiple unrelated aggregates can be loaded together without authorization issues" do
      # Test loading multiple unrelated aggregates simultaneously
      {:ok, user} = Ash.create(User, %{name: "MultiAuth", email: "multi@example.com"})
      {:ok, _profile} = Ash.create(Profile, %{name: "MultiAuth", age: 28, active: true})

      {:ok, _report} =
        Ash.create(Report, %{
          title: "MultiAuth Report",
          author_name: "MultiAuth",
          score: 88,
          inserted_at: ~U[2024-01-01 15:00:00Z]
        })

      # Loading multiple unrelated aggregates should work
      user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.load([
          :matching_name_profiles_count,
          :total_active_profiles,
          :latest_authored_report,
          :total_report_score
        ])
        |> Ash.read_one!()

      assert user.matching_name_profiles_count == 1
      # Could include profiles from other tests
      assert user.total_active_profiles >= 1
      assert user.latest_authored_report == "MultiAuth Report"
      assert user.total_report_score == 88
    end

    test "unrelated aggregates respect target resource authorization policies" do
      admin_user = Ash.create!(User, %{name: "Admin", email: "admin@test.com", role: :admin})
      regular_user1 = Ash.create!(User, %{name: "User1", email: "user1@test.com", role: :user})
      regular_user2 = Ash.create!(User, %{name: "User1", email: "user2@test.com", role: :user})

      Ash.create!(SecureProfile, %{
        name: "User1",
        age: 25,
        active: true,
        owner_id: regular_user1.id,
        department: "Engineering"
      })

      Ash.create!(SecureProfile, %{
        name: "User1",
        age: 30,
        active: true,
        owner_id: regular_user2.id,
        department: "Marketing"
      })

      Ash.create!(SecureProfile, %{
        name: "Admin",
        age: 35,
        active: true,
        owner_id: admin_user.id,
        department: "Management"
      })

      user1_result =
        User
        |> Ash.Query.filter(id == ^regular_user1.id)
        |> Ash.Query.load(:secure_profile_count)
        |> Ash.read_one!(actor: regular_user1, authorize?: true)

      assert user1_result.secure_profile_count == 1

      user2_result =
        User
        |> Ash.Query.filter(id == ^regular_user2.id)
        |> Ash.Query.load(:secure_profile_count)
        |> Ash.read_one!(actor: regular_user2, authorize?: true)

      assert user2_result.secure_profile_count == 1

      admin_as_user1 =
        User
        |> Ash.Query.filter(id == ^regular_user1.id)
        |> Ash.Query.load(:secure_profile_count)
        |> Ash.read_one!(actor: admin_user, authorize?: true)

      assert admin_as_user1.secure_profile_count == 2

      admin_result =
        User
        |> Ash.Query.filter(id == ^admin_user.id)
        |> Ash.Query.load(:secure_profile_count)
        |> Ash.read_one!(actor: admin_user, authorize?: true)

      assert admin_result.secure_profile_count == 1
    end
  end

  describe "edge cases" do
    test "unrelated aggregates work with empty result sets" do
      users =
        User
        |> Ash.Query.filter(name == "NonExistent")
        |> Ash.Query.load(:matching_name_profiles_count)
        |> Ash.read!()

      # Should be empty, but aggregate should still work
      assert users == []
    end

    test "unrelated aggregates work with filters that return no results" do
      {:ok, user} = Ash.create(User, %{name: "Unique", email: "unique@example.com"})

      # No profiles with name "Unique" exist
      loaded_user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.load(:matching_name_profiles_count)
        |> Ash.read_one!()

      assert loaded_user.matching_name_profiles_count == 0
    end

    test "unrelated aggregates work with complex filter expressions" do
      {:ok, user} =
        Ash.create(User, %{name: "ComplexTest", age: 25, email: "complex@example.com"})

      # Create profiles with various attributes
      {:ok, _profile1} =
        Ash.create(Profile, %{name: "ComplexTest", age: 25, bio: "Bio contains ComplexTest"})

      {:ok, _profile2} =
        Ash.create(Profile, %{name: "ComplexTest", age: 30, bio: "Different bio"})

      {:ok, _profile3} =
        Ash.create(Profile, %{name: "Other", age: 25, bio: "ComplexTest mentioned"})

      # Test parent() with boolean AND
      loaded_user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.aggregate(:same_name_and_age, :count, Profile,
          query: [filter: expr(name == parent(name) and age == parent(age))]
        )
        |> Ash.read_one!()

      assert loaded_user.aggregates.same_name_and_age == 1

      # Test parent() with OR conditions
      loaded_user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.aggregate(:name_or_bio_match, :count, Profile,
          query: [filter: expr(name == parent(name) or contains(bio, parent(name)))]
        )
        |> Ash.read_one!()

      assert loaded_user.aggregates.name_or_bio_match == 3

      # Test parent() with comparison operators
      loaded_user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.aggregate(:older_profiles, :count, Profile,
          query: [filter: expr(name == parent(name) and age > parent(age))]
        )
        |> Ash.read_one!()

      assert loaded_user.aggregates.older_profiles == 1
    end

    test "parent() works with nested conditional expressions" do
      {:ok, user} = Ash.create(User, %{name: "NestedTest", age: 30, email: "nested@example.com"})

      {:ok, _profile1} = Ash.create(Profile, %{name: "NestedTest", age: 25, bio: "Young"})
      {:ok, _profile2} = Ash.create(Profile, %{name: "NestedTest", age: 35, bio: "Old"})
      {:ok, _profile3} = Ash.create(Profile, %{name: "Other", age: 30, bio: "Same age"})

      # Test nested parentheses with parent()
      loaded_user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.aggregate(:complex_condition, :count, Profile,
          query: [filter: expr(name == parent(name) and (age < parent(age) or age > parent(age)))]
        )
        |> Ash.read_one!()

      assert loaded_user.aggregates.complex_condition == 2
    end

    test "parent() works with string functions" do
      {:ok, user} = Ash.create(User, %{name: "StringTest", email: "string@example.com"})

      {:ok, _profile1} =
        Ash.create(Profile, %{name: "StringTest", bio: "StringTest is mentioned here"})

      {:ok, _profile2} =
        Ash.create(Profile, %{name: "DifferentName", bio: "StringTest appears in bio"})

      {:ok, _profile3} = Ash.create(Profile, %{name: "StringTest", bio: "No mention"})

      # Test parent() with string contains function
      loaded_user =
        User
        |> Ash.Query.filter(id == ^user.id)
        |> Ash.Query.aggregate(:bio_mentions_name, :count, Profile,
          query: [filter: expr(contains(bio, parent(name)))]
        )
        |> Ash.read_one!()

      assert loaded_user.aggregates.bio_mentions_name == 2
    end
  end
end
