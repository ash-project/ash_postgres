defmodule PassIfOriginalDataPresent do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  def describe(_options), do: "original data present"

  def match?(_, _, _) do
    true
  end

  def requires_original_data?(_, _) do
    true
  end
end

defmodule AshPostgres.Test.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  policies do
    bypass action_type(:read) do
      # Check that the post is in the same org as actor
      authorize_if(relates_to_actor_via([:organization, :users]))
    end

    policy action(:allow_any) do
      authorize_if(always())
    end

    policy action(:requires_initial_data) do
      authorize_if(PassIfOriginalDataPresent)
    end

    policy action_type(:update) do
      authorize_if(action(:requires_initial_data))
      authorize_if(relates_to_actor_via([:author, :authors_with_same_first_name]))
      authorize_unless(changing_attributes(title: [from: "good", to: "bad"]))
    end
  end

  field_policies do
    field_policy :* do
      authorize_if(always())
    end
  end

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
      index([:uniq_custom_one, :uniq_custom_two],
        unique: true,
        concurrently: true,
        message: "dude what the heck"
      )
    end
  end

  resource do
    base_filter(expr(type == type(:sponsored, ^Ash.Type.Atom)))
  end

  actions do
    default_accept(:*)

    defaults([:destroy])

    destroy :destroy_with_confirm do
      require_atomic?(false)
      argument(:confirm, :string, allow_nil?: false)

      change(fn changeset, _ ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          if changeset.arguments.confirm == "CONFIRM" do
            changeset
          else
            Ash.Changeset.add_error(changeset, field: :confirm, message: "must type CONFIRM")
          end
        end)
      end)
    end

    destroy :soft_destroy_with_confirm do
      require_atomic?(false)
      argument(:confirm, :string, allow_nil?: false)

      change(fn changeset, _ ->
        Ash.Changeset.before_action(changeset, fn changeset ->
          if changeset.arguments.confirm == "CONFIRM" do
            changeset
          else
            Ash.Changeset.add_error(changeset, field: :confirm, message: "must type CONFIRM")
          end
        end)
      end)
    end

    update :update do
      primary?(true)
      require_atomic?(false)
    end

    update :change_title_to_foo_unless_its_already_foo do
      validate(attribute_does_not_equal(:title, "foo"))
      change(set_attribute(:title, "foo"))
    end

    read :title_is_foo do
      filter(expr(title == "foo"))
    end

    read :read do
      primary?(true)
    end

    read(:allow_any)

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

    update :increment_score do
      argument(:amount, :integer, default: 1)
      change(atomic_update(:score, expr((score || 0) + ^arg(:amount))))
    end

    update :requires_initial_data do
      argument(:amount, :integer, default: 1)
      change(atomic_update(:score, expr((score || 0) + ^arg(:amount))))
    end

    update :manual_update do
      require_atomic?(false)
      manual(AshPostgres.Test.Post.ManualUpdate)
    end
  end

  identities do
    identity(:uniq_one_and_two, [:uniq_one, :uniq_two])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)

    attribute(:title, :string) do
      public?(true)
      source(:title_column)
    end

    attribute(:score, :integer, public?: true)
    attribute(:public, :boolean, public?: true)
    attribute(:category, :ci_string, public?: true)
    attribute(:type, :atom, default: :sponsored, writable?: false, public?: false)
    attribute(:price, :integer, public?: true)
    attribute(:decimal, :decimal, default: Decimal.new(0), public?: true)
    attribute(:status, AshPostgres.Test.Types.Status, public?: true)
    attribute(:status_enum, AshPostgres.Test.Types.StatusEnum, public?: true)

    attribute(:status_enum_no_cast, AshPostgres.Test.Types.StatusEnumNoCast,
      source: :status_enum,
      public?: true
    )

    attribute(:point, AshPostgres.Test.Point, public?: true)
    attribute(:composite_point, AshPostgres.Test.CompositePoint, public?: true)
    attribute(:stuff, :map, public?: true)
    attribute(:list_of_stuff, {:array, :map}, public?: true)
    attribute(:uniq_one, :string, public?: true)
    attribute(:uniq_two, :string, public?: true)
    attribute(:uniq_custom_one, :string, public?: true)
    attribute(:uniq_custom_two, :string, public?: true)

    attribute :list_containing_nils, {:array, :string} do
      public?(true)
      constraints(nil_items?: true)
    end

    create_timestamp(:created_at, writable?: true, public?: true)
    update_timestamp(:updated_at, writable?: true, public?: true)
  end

  code_interface do
    define(:create, args: [:title])
    define(:get_by_id, action: :read, get_by: [:id])
    define(:increment_score, args: [{:optional, :amount}])
    define(:destroy)
  end

  relationships do
    belongs_to :organization, AshPostgres.Test.Organization do
      public?(true)
      attribute_writable?(true)
    end

    belongs_to(:current_user_author, AshPostgres.Test.Author) do
      source_attribute(:author_id)
      define_attribute?(false)
      filter(expr(^actor(:id) == id))
    end

    belongs_to(:author, AshPostgres.Test.Author) do
      public?(true)
    end

    has_many :posts_with_matching_title, __MODULE__ do
      public?(true)
      no_attributes?(true)
      filter(expr(parent(title) == title and parent(id) != id))
    end

    has_many(:comments, AshPostgres.Test.Comment, destination_attribute: :post_id, public?: true)

    has_many :comments_matching_post_title, AshPostgres.Test.Comment do
      public?(true)
      filter(expr(title == parent_expr(title)))
    end

    has_many :popular_comments, AshPostgres.Test.Comment do
      public?(true)
      destination_attribute(:post_id)
      filter(expr(likes > 10))
    end

    has_many :comments_containing_title, AshPostgres.Test.Comment do
      public?(true)
      manual(AshPostgres.Test.Post.CommentsContainingTitle)
    end

    has_many :comments_with_high_rating, AshPostgres.Test.Comment do
      public?(true)
      filter(expr(ratings.score > 5))
    end

    has_many(:ratings, AshPostgres.Test.Rating,
      public?: true,
      destination_attribute: :resource_id,
      relationship_context: %{data_layer: %{table: "post_ratings"}}
    )

    has_many(:post_links, AshPostgres.Test.PostLink,
      public?: true,
      destination_attribute: :source_post_id,
      filter: [state: :active]
    )

    many_to_many(:linked_posts, __MODULE__,
      public?: true,
      through: AshPostgres.Test.PostLink,
      join_relationship: :post_links,
      source_attribute_on_join_resource: :source_post_id,
      destination_attribute_on_join_resource: :destination_post_id
    )

    many_to_many(:followers, AshPostgres.Test.User,
      public?: true,
      through: AshPostgres.Test.PostFollower,
      source_attribute_on_join_resource: :post_id,
      destination_attribute_on_join_resource: :follower_id,
      read_action: :active
    )

    has_many(:views, AshPostgres.Test.PostView) do
      public?(true)
    end
  end

  validations do
    validate(attribute_does_not_equal(:title, "not allowed"))
  end

  calculations do
    calculate(
      :author_has_post_with_follower_named_fred,
      :boolean,
      expr(
        exists(
          author.posts,
          has_follower_named_fred
        )
      )
    )

    calculate(
      :has_no_followers,
      :boolean,
      expr(is_nil(author.posts.followers))
    )

    calculate(:score_after_winning, :integer, expr((score || 0) + 1))
    calculate(:negative_score, :integer, expr(-score))
    calculate(:category_label, :ci_string, expr("(" <> category <> ")"))
    calculate(:score_with_score, :string, expr(score <> score))
    calculate(:foo_bar_from_stuff, :string, expr(stuff[:foo][:bar]))

    calculate(
      :has_follower_named_fred,
      :boolean,
      expr(exists(followers, name == "fred"))
    )

    calculate(
      :composite_origin,
      AshPostgres.Test.CompositePoint,
      expr(composite_type(%{x: 0, y: 0}, AshPostgres.Test.CompositePoint))
    )

    calculate(
      :score_map,
      :map,
      expr(%{
        negative_score: %{foo: negative_score, bar: negative_score}
      })
    )

    calculate(
      :count_of_comments_called_baz,
      :integer,
      expr(count(comments, query: [filter: expr(title == "baz")]))
    )

    calculate(
      :agg_map,
      :map,
      expr(%{
        called_foo: count(comments, query: [filter: expr(title == "foo")]),
        called_bar: count(comments, query: [filter: expr(title == "bar")]),
        called_baz: count_of_comments_called_baz
      })
    )

    calculate(:c_times_p, :integer, expr(count_of_comments * count_of_linked_posts),
      load: [:count_of_comments, :count_of_linked_posts]
    )

    calculate :similarity,
              :boolean,
              expr(fragment("(to_tsvector(?) @@ ?)", title, ^arg(:search))) do
      argument(:search, AshPostgres.Tsquery, allow_expr?: true, allow_nil?: false)
    end

    calculate :query, AshPostgres.Tsquery, expr(fragment("to_tsquery(?)", ^arg(:search))) do
      argument(:search, :string, allow_expr?: true, allow_nil?: false)
    end

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

    calculate(
      :has_future_comment,
      :boolean,
      expr(latest_comment_created_at > fragment("now()") || type(false, :boolean))
    )

    calculate(:price_times_2, :integer, expr(price * 2))

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

    calculate(:author_count_of_posts, :integer, expr(author.count_of_posts_with_calc))

    calculate(
      :sum_of_author_count_of_posts,
      :integer,
      expr(sum(author, field: :count_of_posts))
    )

    calculate(:author_count_of_posts_agg, :integer, expr(author.count_of_posts))

    calculate(
      :price_string,
      :string,
      CalculatePostPriceString
    )

    calculate(
      :price_string_with_currency_sign,
      :string,
      CalculatePostPriceStringWithSymbol
    )

    calculate(:author_first_name_calc, :string, expr(author.first_name))

    calculate(:author_profile_description_from_agg, :string, expr(author_profile_description))
  end

  aggregates do
    count(:count_of_comments, :comments)
    count(:count_of_linked_posts, :linked_posts)

    count :count_of_comments_called_match, :comments do
      filter(title: "match")
    end

    exists :has_comment_called_match, :comments do
      filter(title: "match")
    end

    count(:count_of_comments_containing_title, :comments_containing_title)

    first :first_comment, :comments, :title do
      sort(title: :asc_nils_last)
    end

    first :last_comment, :comments, :title do
      sort(title: :desc, title: :asc)
    end

    first(:author_first_name, :author, :first_name)

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

    list :uniq_comment_titles, :comments, :title do
      uniq?(true)
      sort(title: :asc_nils_last)
    end

    count :count_comment_titles, :comments do
      field(:title)
    end

    count :count_uniq_comment_titles, :comments do
      field(:title)
      uniq?(true)
    end

    count(:count_of_ratings, :ratings)

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

    first(:author_profile_description, :author, :description)
  end
end

defmodule CalculatePostPriceString do
  @moduledoc false
  use Ash.Resource.Calculation

  @impl true
  def load(_, _, _), do: [:price]

  @impl true
  def calculate(records, _, _) do
    Enum.map(records, fn %{price: price} ->
      dollars = div(price, 100)
      cents = rem(price, 100)
      "#{dollars}.#{cents}"
    end)
  end
end

defmodule CalculatePostPriceStringWithSymbol do
  @moduledoc false
  use Ash.Resource.Calculation

  @impl true
  def load(_, _, _), do: [:price_string]

  @impl true
  def calculate(records, _, _) do
    Enum.map(records, fn %{price_string: price_string} ->
      "#{price_string}$"
    end)
  end
end

defmodule AshPostgres.Test.Post.ManualUpdate do
  @moduledoc false
  use Ash.Resource.ManualUpdate

  def update(changeset, _opts, _context) do
    {
      :ok,
      changeset.data
      |> Ash.Changeset.for_update(:update, changeset.attributes)
      |> Ash.Changeset.force_change_attribute(:title, "manual")
      |> Ash.Changeset.load(:comments)
      |> Ash.update!()
    }
  end
end
