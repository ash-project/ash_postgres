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

    custom_indexes do
      index [:uniq_custom_one, :uniq_custom_two],
        unique: true,
        concurrently: true,
        message: "dude what the heck"
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

  identities do
    identity(:uniq_one_and_two, [:uniq_one, :uniq_two])
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
    attribute(:uniq_one, :string)
    attribute(:uniq_two, :string)
    attribute(:uniq_custom_one, :string)
    attribute(:uniq_custom_two, :string)
    create_timestamp(:created_at)
    update_timestamp(:updated_at)
  end

  code_interface do
    define_for(AshPostgres.Test.Api)
    define(:get_by_id, action: :read, get_by: [:id])
  end

  relationships do
    belongs_to(:author, AshPostgres.Test.Author)

    has_many(:comments, AshPostgres.Test.Comment, destination_attribute: :post_id)

    has_many :popular_comments, AshPostgres.Test.Comment do
      destination_attribute(:post_id)
      filter(expr(likes > 10))
    end

    has_many :comments_containing_title, AshPostgres.Test.Comment do
      manual(AshPostgres.Test.Post.CommentsContainingTitle)
    end

    has_many(:ratings, AshPostgres.Test.Rating,
      destination_attribute: :resource_id,
      relationship_context: %{data_layer: %{table: "post_ratings"}}
    )

    has_many(:post_links, AshPostgres.Test.PostLink,
      destination_attribute: :source_post_id,
      filter: [state: :active]
    )

    many_to_many(:linked_posts, __MODULE__,
      through: AshPostgres.Test.PostLink,
      join_relationship: :post_links,
      source_attribute_on_join_resource: :source_post_id,
      destination_attribute_on_join_resource: :destination_post_id
    )
  end

  calculations do
    calculate(:category_label, :ci_string, expr("(" <> category <> ")"))

    calculate(:c_times_p, :integer, expr(count_of_comments * count_of_linked_posts),
      load: [:count_of_comments, :count_of_linked_posts]
    )

    calculate(
      :calc_returning_json,
      AshPostgres.Test.Money,
      expr(
        fragment("""
        '{"amount":100, "currency": "usd"}'::json
        """)
      )
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
          fragment("(? <= (? - '1 month'::interval))", now(), created_at),
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

    count(:count_of_comments_containing_title, :comments_containing_title)

    first :first_comment, :comments, :title do
      sort(title: :asc_nils_last)
    end

    max(:highest_comment_rating, [:comments, :ratings], :score)
    min(:lowest_comment_rating, [:comments, :ratings], :score)
    avg(:avg_comment_rating, [:comments, :ratings], :score)

    custom(:comment_authors, [:comments, :author], :string) do
      implementation({AshPostgres.Test.StringAgg, field: :first_name, delimiter: ","})
    end

    first :latest_comment_created_at, :comments, :created_at do
      sort(created_at: :desc)
    end

    list :comment_titles, :comments, :title do
      sort(title: :asc_nils_last)
    end

    list :comment_titles_with_5_likes, :comments, :title do
      sort(title: :asc_nils_last)
      filter(expr(likes >= 5))
    end

    sum(:sum_of_comment_likes, :comments, :likes)
    sum(:sum_of_comment_likes_with_default, :comments, :likes, default: 0)

    sum :sum_of_popular_comment_rating_scores, [:comments, :ratings], :score do
      filter(expr(score > 5))
    end

    sum(:sum_of_popular_comment_rating_scores_2, [:comments, :popular_ratings], :score)

    sum :sum_of_comment_likes_called_match, :comments, :likes do
      filter(title: "match")
    end

    # All of them will, but we want to test a related field
    count :count_of_comments_that_have_a_post, :comments do
      filter(expr(not is_nil(post.id)))
    end

    # All of them will, but we want to test a related field
    count :count_of_comments_that_have_a_post_with_exists, :comments do
      filter(expr(exists(post, not is_nil(id))))
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

    count :count_of_popular_comment_ratings, [:comments, :ratings] do
      filter(expr(score > 10))
    end

    list :ten_most_popular_comments, [:comments, :ratings], :id do
      filter(expr(score > 10))
      sort(score: :desc)
    end

    first :highest_rating, [:comments, :ratings], :score do
      sort(score: :desc)
    end

    first :latest_arbitrary_timestamp, :comments, :arbitrary_timestamp do
      sort(arbitrary_timestamp: :desc)
    end
  end
end
