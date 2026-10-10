# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.ResourceBasedInlineAggregatesTest do
  @moduledoc """
  Regression tests for resource-based inline aggregates across PostgreSQL schemas.

  These tests are here to ensure that inline aggregates continue to work when
  target resources are stored within different database schemas.
  """
  use AshPostgres.RepoCase, async: false

  defmodule CrossSchema.Domain do
    use Ash.Domain

    resources do
      allow_unregistered?(true)
    end
  end

  defmodule CrossSchema.Report do
    use Ash.Resource, domain: CrossSchema.Domain, data_layer: AshPostgres.DataLayer

    postgres do
      repo AshPostgres.TestRepo
      schema "task_report_schema"
      table "reports"
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, public?: true)
      attribute(:author_name, :string, public?: true)
      attribute(:score, :integer, public?: true)
      attribute(:inserted_at, :utc_datetime_usec, public?: true)
    end

    actions do
      defaults([:read, create: :*])
    end
  end

  defmodule CrossSchema.Activity do
    use Ash.Resource, domain: CrossSchema.Domain, data_layer: AshPostgres.DataLayer

    postgres do
      repo AshPostgres.TestRepo
      schema "task_activity_schema"
      table "activities"
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, public?: true)
      attribute(:active, :boolean, public?: true)
    end

    actions do
      defaults([:read, create: :*])
    end
  end

  defmodule CrossSchema.Profile do
    use Ash.Resource, domain: CrossSchema.Domain, data_layer: AshPostgres.DataLayer

    postgres do
      repo AshPostgres.TestRepo
      schema "task_profile_schema"
      table "profiles"
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, public?: true)
      attribute(:active, :boolean, public?: true)
    end

    actions do
      defaults([:read, create: :*])
    end

    calculations do
      calculate(
        :latest_report,
        :string,
        expr(
          first(CrossSchema.Report,
            field: :title,
            query: [
              filter: expr(author_name == parent(name)),
              sort: [inserted_at: :desc]
            ]
          )
        )
      )

      calculate(
        :stats,
        :map,
        expr(%{
          profile_count: count(CrossSchema.Profile, filter: expr(name == parent(name))),
          active_activity_count:
            count(CrossSchema.Activity,
              filter: expr(active == true and name == parent(name))
            ),
          latest_report:
            first(CrossSchema.Report,
              field: :title,
              query: [
                filter: expr(author_name == parent(name)),
                sort: [inserted_at: :desc]
              ]
            )
        })
      )
    end
  end

  defp setup_cross_schema_data(repo) do
    repo.query!("CREATE SCHEMA task_profile_schema")
    repo.query!("CREATE SCHEMA task_activity_schema")
    repo.query!("CREATE SCHEMA task_report_schema")

    repo.query!(
      "CREATE TABLE task_profile_schema.profiles (id uuid PRIMARY KEY, name text, active boolean)"
    )

    repo.query!(
      "CREATE TABLE task_activity_schema.activities (id uuid PRIMARY KEY, name text, active boolean)"
    )

    repo.query!(
      "CREATE TABLE task_report_schema.reports (id uuid PRIMARY KEY, title text, author_name text, score integer, inserted_at timestamptz)"
    )

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    eight_days_ago = DateTime.add(now, -8, :day)
    yesterday = DateTime.add(now, -1, :day)

    Ash.create!(CrossSchema.Profile, %{name: "Alice", active: true})
    Ash.create!(CrossSchema.Activity, %{name: "Alice", active: true})

    Ash.create!(CrossSchema.Report, %{
      title: "Older",
      author_name: "Alice",
      score: 10,
      inserted_at: eight_days_ago
    })

    Ash.create!(CrossSchema.Report, %{
      title: "Latest",
      author_name: "Alice",
      score: 20,
      inserted_at: yesterday
    })

    Ash.create!(CrossSchema.Report, %{
      title: "Other author",
      author_name: "Bob",
      score: 100,
      inserted_at: yesterday
    })
  end

  test "one inline aggregate looks up target resource from its configured schema" do
    setup_cross_schema_data(AshPostgres.TestRepo)

    query = Ash.Query.load(CrossSchema.Profile, :latest_report)

    assert %{latest_report: "Latest"} = Ash.read_one!(query)
  end

  test "multiple inline aggregates preserve each target resource's configured schema" do
    setup_cross_schema_data(AshPostgres.TestRepo)

    query = Ash.Query.load(CrossSchema.Profile, :stats)

    assert %{stats: %{profile_count: 1, active_activity_count: 1, latest_report: "Latest"}} =
             Ash.read_one!(query)
  end
end
