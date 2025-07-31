defmodule AshPostgres.Test.UnrelatedAggregatesTest.User do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshPostgres.Test.UnrelatedAggregatesTest.{Profile, Report, SecureProfile}

  postgres do
    table("unrelated_users")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
    attribute(:age, :integer, public?: true)
    attribute(:email, :string, public?: true)
    attribute(:role, :atom, public?: true, default: :user)
  end

  # Test basic unrelated aggregates
  aggregates do
    # Count of profiles with matching name
    count :matching_name_profiles_count, Profile do
      filter(expr(name == parent(name)))
      public?(true)
    end

    # Count of all active profiles (no parent filter)
    count :total_active_profiles, Profile do
      filter(expr(active == true))
      public?(true)
    end

    # First report with matching author name
    first :latest_authored_report, Report, :title do
      filter(expr(author_name == parent(name)))
      sort(inserted_at: :desc)
      public?(true)
    end

    # Sum of report scores for matching author
    sum :total_report_score, Report, :score do
      filter(expr(author_name == parent(name)))
      public?(true)
    end

    # Exists check for profiles with same name
    exists :has_matching_name_profile, Profile do
      filter(expr(name == parent(name)))
      public?(true)
    end

    # List of all profile names with same name (should be just one usually)
    list :matching_profile_names, Profile, :name do
      filter(expr(name == parent(name)))
      public?(true)
    end

    # Max age of profiles with same name
    max :max_age_same_name, Profile, :age do
      filter(expr(name == parent(name)))
      public?(true)
    end

    # Min age of profiles with same name
    min :min_age_same_name, Profile, :age do
      filter(expr(name == parent(name)))
      public?(true)
    end

    # Average age of profiles with same name
    avg :avg_age_same_name, Profile, :age do
      filter(expr(name == parent(name)))
      public?(true)
    end

    # Secure aggregate - should respect authorization policies
    count :secure_profile_count, SecureProfile do
      filter(expr(name == parent(name)))
      public?(true)
    end
  end

  # Test unrelated aggregates in calculations
  calculations do
    calculate :matching_profiles_summary,
              :string,
              expr("Found " <> type(matching_name_profiles_count, :string) <> " profiles") do
      public?(true)
    end

    calculate :inline_profile_count,
              :integer,
              expr(count(Profile, filter: expr(name == parent(name)))) do
      public?(true)
    end

    calculate :inline_latest_report_title,
              :string,
              expr(
                first(Report,
                  field: :title,
                  query: [
                    filter: expr(author_name == parent(name)),
                    sort: [inserted_at: :desc]
                  ]
                )
              ) do
      public?(true)
    end

    calculate :inline_total_score,
              :integer,
              expr(
                sum(Report,
                  field: :score,
                  query: [
                    filter: expr(author_name == parent(name))
                  ]
                )
              ) do
      public?(true)
    end

    calculate :complex_calculation,
              :map,
              expr(%{
                profile_count: count(Profile, filter: expr(name == parent(name))),
                latest_report:
                  first(Report,
                    field: :title,
                    query: [
                      filter: expr(author_name == parent(name)),
                      sort: [inserted_at: :desc]
                    ]
                  ),
                total_score:
                  sum(Report,
                    field: :score,
                    query: [
                      filter: expr(author_name == parent(name))
                    ]
                  )
              }) do
      public?(true)
    end
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
