defmodule AshPostgres.Test.Post do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("posts")
    repo(AshPostgres.TestRepo)
    base_filter_sql("type = 'sponsored'")

    check_constraints do
      check_constraint(:price, "price_must_be_positive",
        message: "yo, bad price",
        check: "price > 0"
      )
    end
  end

  resource do
    base_filter(expr(type == type(:sponsored, ^Ash.Type.Atom)))
  end

  actions do
    defaults([:update, :destroy])

    read :read do
      primary?(true)
    end

    read :paginated do
      pagination(offset?: true, required?: true, countable: true)
    end

    create :create do
      primary?(true)
      argument(:rating, :map)

      change(
        manage_relationship(:rating, :ratings,
          on_missing: :ignore,
          on_no_match: :create,
          on_match: :create
        )
      )
    end
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:title, :string)
    attribute(:score, :integer)
    attribute(:public, :boolean)
    attribute(:category, :ci_string)
    attribute(:type, :atom, default: :sponsored, private?: true, writable?: false)
    attribute(:price, :integer)
    attribute(:decimal, :decimal, default: Decimal.new(0))
    attribute(:status, AshPostgres.Test.Types.Status)
    attribute(:status_enum, AshPostgres.Test.Types.StatusEnum)
    attribute(:status_enum_no_cast, AshPostgres.Test.Types.StatusEnumNoCast, source: :status_enum)
    attribute(:point, AshPostgres.Test.Point)
    create_timestamp(:created_at)
  end

  relationships do
    belongs_to(:author, AshPostgres.Test.Author)

    has_many(:comments, AshPostgres.Test.Comment, destination_field: :post_id)

    has_many :popular_comments, AshPostgres.Test.Comment do
      destination_field(:post_id)
      # filter(expr(likes > 10))
    end

    has_many(:ratings, AshPostgres.Test.Rating,
      destination_field: :resource_id,
      relationship_context: %{data_layer: %{table: "post_ratings"}}
    )

    many_to_many(:linked_posts, __MODULE__,
      through: AshPostgres.Test.PostLink,
      source_field_on_join_table: :source_post_id,
      destination_field_on_join_table: :destination_post_id
    )
  end

  calculations do
    calculate(:c_times_p, :integer, expr(count_of_comments * count_of_linked_posts),
      load: [:count_of_comments, :count_of_linked_posts]
    )

    calculate(
      :has_future_arbitrary_timestamp,
      :boolean,
      expr(latest_arbitrary_timestamp > fragment("now()"))
    )

    calculate(:has_future_comment, :boolean, expr(latest_comment_created_at > fragment("now()")))

    calculate(
      :was_created_in_the_last_month,
      :boolean,
      expr(
        # This is written in a silly way on purpose, to test a regression
        if(
          fragment("(? <= (now() - '1 month'::interval))", created_at),
          true,
          false
        )
      )
    )
  end

  aggregates do
    count(:count_of_comments, :comments)
    count(:count_of_linked_posts, :linked_posts)

    count :count_of_comments_called_match, :comments do
      filter(title: "match")
    end

    first :first_comment, :comments, :title do
      sort(title: :asc_nils_last)
    end

    first :latest_comment_created_at, :comments, :created_at do
      sort(created_at: :desc)
    end

    list :comment_titles, :comments, :title do
      sort(title: :asc_nils_last)
    end

    sum(:sum_of_comment_likes, :comments, :likes)
    sum(:sum_of_comment_likes_with_default, :comments, :likes, default: 0)

    sum :sum_of_comment_likes_called_match, :comments, :likes do
      filter(title: "match")
    end

    # All of them will, but we want to test a related field
    count :count_of_comments_that_have_a_post, :comments do
      filter(expr(not is_nil(post.id)))
    end

    count :count_of_popular_comments, :comments do
      filter(expr(not is_nil(popular_ratings.id)))
    end

    sum :sum_of_recent_popular_comment_likes, :popular_comments, :likes do
      # not(is_nil(post_category)) is silly but its here for tests
      filter(expr(created_at > ago(10, :day) and not is_nil(post_category)))
    end

    count :count_of_recent_popular_comments, :popular_comments do
      # not(is_nil(post_category)) is silly but its here for tests
      filter(expr(created_at > ago(10, :day) and not is_nil(post_category)))
    end

    count(:count_of_comment_ratings, [:comments, :ratings])

    first :highest_rating, [:comments, :ratings], :score do
      sort(score: :desc)
    end

    first :latest_arbitrary_timestamp, :comments, :arbitrary_timestamp do
      sort(arbitrary_timestamp: :desc)
    end
  end
end
