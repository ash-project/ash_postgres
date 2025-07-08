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

defmodule HasNoComments do
  @moduledoc false
  use Ash.Resource.Validation

  def atomic(changeset, _opts, context) do
    # Test multiple types of aggregates in a single validation
    condition =
      case changeset.context.aggregate do
        :exists ->
          expr(exists(comments, true))

        :list ->
          expr(length(list(comments, field: :id)) > 0)

        :count ->
          expr(count(comments) > 0)

        :combined ->
          expr(
            exists(comments, true) and
              length(list(comments, field: :id)) > 0 and
              count(comments) > 0
          )
      end

    [
      {:atomic, [], condition,
       expr(
         error(^Ash.Error.Changes.InvalidChanges, %{
           message: ^context.message || "Post has comments"
         })
       )}
    ]
  end
end

defmodule CiCategory do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :ci_string
end

defmodule AshPostgres.Test.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [
      Ash.Policy.Authorizer
    ]

  require Ash.Sort

  defmodule TitleTwice do
    @moduledoc false
    use Ash.Resource.Calculation

    def load(_, _, _), do: [:title]

    # it would always be a bug for these
    # to produce different values
    # but we do it here for testing
    def calculate(records, _, _) do
      Enum.map(records, fn record ->
        "in calc:" <> record.title <> record.title
      end)
    end

    def expression(_, _) do
      expr("in expr:" <> title <> title)
    end
  end

  policies do
    bypass action_type(:read) do
      # Check that the post is in the same org as actor
      authorize_if(relates_to_actor_via([:organization, :users]))
    end

    policy action(:read_with_policy_with_parent) do
      authorize_if(
        relates_to_actor_via([:posts_with_my_organization_name_as_a_title, :organization, :users])
      )
    end

    policy action(:allow_any) do
      authorize_if(always())
    end

    policy action(:requires_initial_data) do
      authorize_if(PassIfOriginalDataPresent)
    end

    bypass action(:update_if_author) do
      authorize_if(relates_to_actor_via(:author))
    end

    policy action_type(:update) do
      authorize_if(action(:requires_initial_data))
      authorize_if(relates_to_actor_via([:author, :authors_with_same_first_name]))
      authorize_unless(changing_attributes(title: [from: "good", to: "bad"]))
    end

    policy action(:create) do
      authorize_unless(changing_attributes(title: [to: "worst"]))
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

    calculations_to_sql(upper_thing: "UPPER(uniq_on_upper)")
    identity_wheres_to_sql(uniq_if_contains_foo: "(uniq_if_contains_foo LIKE '%foo%')")

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

    defaults([:read, :destroy])

    read :with_version_check do
      argument(:version, :integer)

      filter(expr(type(^arg(:version), :string) in ["1", "2"]))
    end

    read :first_and_last_post do
      prepare(fn query, _ ->
        Ash.Query.combination_of(query, [
          Ash.Query.Combination.base(
            limit: 1,
            sort: [created_at: :desc]
          ),
          Ash.Query.Combination.union(
            limit: 1,
            sort: [created_at: :asc]
          )
        ])
      end)
    end

    read :first_and_last_two_posts do
      prepare(fn query, _ ->
        Ash.Query.combination_of(query, [
          Ash.Query.Combination.base(
            limit: 2,
            sort: [created_at: :desc]
          ),
          Ash.Query.Combination.union(
            limit: 2,
            sort: [created_at: :asc]
          )
        ])
      end)
    end

    update :subtract_integer_from_decimal do
      argument(:amount, :integer, allow_nil?: false)
      change(atomic_update(:decimal, expr(decimal + -(^arg(:amount)))))
    end

    update :subtract_from_decimal do
      argument(:amount, :decimal, allow_nil?: false)
      change(atomic_update(:decimal, expr(decimal + -(^arg(:amount)))))
    end

    update :add_to_limited_score do
      argument(:amount, :integer, allow_nil?: false)
      change(atomic_update(:limited_score, expr((limited_score || 0) + ^arg(:amount))))
    end

    update :validate_absent_non_atomically do
      require_atomic?(false)
      accept([:title])
      validate(absent(:title))
    end

    update :validate_absent do
      accept([:title])
      validate(absent(:title))
    end

    update :change_nothing do
      accept([])
      require_atomic?(false)
      change(fn changeset, _ -> changeset end)
    end

    update :change_nothing_atomic do
      accept([])
      require_atomic?(true)
    end

    update :change_title do
      accept([:title])
      require_atomic?(false)
      change(fn changeset, _ -> changeset end)
    end

    update :change_title_atomic do
      accept([:title])
      require_atomic?(true)
    end

    destroy :destroy_only_freds do
      change(filter(expr(title == "fred")))
    end

    destroy :destroy_if_no_comments do
      validate HasNoComments do
        message "Can only delete if Post has no comments"
      end
    end

    update :update_if_no_comments do
      validate HasNoComments do
        message "Can only update if Post has no comments"
      end
    end

    destroy :destroy_if_no_comments_non_atomic do
      require_atomic?(false)

      validate HasNoComments do
        message "Can only delete if Post has no comments"
      end
    end

    update :update_if_no_comments_non_atomic do
      require_atomic?(false)

      validate HasNoComments do
        message "Can only update if Post has no comments"
      end
    end

    update :update_only_freds do
      change(filter(expr(title == "fred")))
    end

    update :set_title_to_sum_of_author_count_of_posts do
      change(atomic_update(:title, expr("#{sum_of_author_count_of_posts}")))
    end

    update :set_title_to_author_profile_description do
      change(atomic_update(:title, expr(author.profile_description)))
    end

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

    update :set_attributes_from_parent do
      require_atomic?(false)

      change(
        atomic_update(
          :title,
          expr(
            if is_nil(parent_post_id) do
              author.title
            else
              parent_post.author.first_name
            end
          )
        )
      )
    end

    update :update_metadata do
      accept([:metadata])
    end

    destroy :cascade_destroy do
      change(cascade_destroy(:high_ratings, after_action?: false))
    end

    update :update do
      primary?(true)
      require_atomic?(false)
    end

    update :atomic_update do
    end

    update :update_if_author do
      require_atomic?(false)
    end

    update(:dont_validate)

    update :change_title_to_foo_unless_its_already_foo do
      validate(attribute_does_not_equal(:title, "foo"))
      change(set_attribute(:title, "foo"))
    end

    read :title_is_foo do
      filter(expr(title == "foo"))
    end

    read :read_with_policy_with_parent do
    end

    read :category_matches do
      argument(:category, CiCategory)
      filter(expr(category == ^arg(:category)))
    end

    read :keyset do
      pagination do
        keyset?(true)
        countable(true)
        required?(false)
      end
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

    defmodule HasBeforeAction do
      @moduledoc false
      use Ash.Resource.Change

      def change(changeset, _, _) do
        Ash.Changeset.before_action(changeset, fn changeset ->
          Ash.Changeset.force_change_attribute(changeset, :title, "before_action")
        end)
      end
    end

    create :create_with_before_action do
      change(HasBeforeAction)
    end

    create :upsert_with_filter do
      upsert?(true)
      upsert_identity(:uniq_if_contains_foo)
      upsert_fields([:price])

      change(fn changeset, _ ->
        Ash.Changeset.filter(changeset, expr(price != fragment("EXCLUDED.price")))
      end)
    end

    create :upsert_with_no_filter do
      upsert?(true)
      upsert_identity(:uniq_if_contains_foo)
      upsert_fields([:price])
    end

    update :set_title_from_author do
      change(atomic_update(:title, expr(author.first_name)))
    end

    update :increment_score do
      argument(:amount, :integer, default: 1)
      change(atomic_update(:score, expr((score || 0) + ^arg(:amount))))
    end

    update :review do
      change(
        after_action(fn changeset, record, _context ->
          new_model = {1.0, 2.0, 3.0}

          record
          |> Ash.Changeset.for_update(:atomic_update)
          |> Ash.Changeset.force_change_attribute(:model, new_model)
          |> Ash.update()
        end)
      )

      require_atomic?(false)
    end

    update :requires_initial_data do
      argument(:amount, :integer, default: 1)
      change(atomic_update(:score, expr((score || 0) + ^arg(:amount))))
    end

    update :manual_update do
      require_atomic?(false)
      manual(AshPostgres.Test.Post.ManualUpdate)
    end

    update :update_constrained_int do
      argument(:amount, :integer, allow_nil?: false)
      change(atomic_update(:constrained_int, expr((constrained_int || 0) + ^arg(:amount))))

      validate(compare(:constrained_int, greater_than_or_equal_to: 2),
        message: "You cannot select less than two."
      )
    end

    update :optimistic_lock do
      accept([:title])
      change(optimistic_lock(:version))
    end

    destroy :optimistic_lock_destroy do
      change(optimistic_lock(:version))
    end

    read :read_with_related_list_agg_filter do
      pagination(keyset?: true, default_limit: 25)
      filter(expr(count_nils(latest_comment.linked_comment_post_ids) == 0))
    end
  end

  identities do
    identity(:uniq_one_and_two, [:uniq_one, :uniq_two])
    identity(:uniq_on_upper, [:upper_thing])

    identity(:uniq_if_contains_foo, [:uniq_if_contains_foo]) do
      where expr(contains(uniq_if_contains_foo, "foo"))
    end
  end

  attributes do
    uuid_primary_key(:id, writable?: true)

    attribute(:version, :integer, allow_nil?: false, default: 1)

    attribute(:title, :string) do
      public?(true)
      source(:title_column)
    end

    attribute :not_selected_by_default, :string do
      select_by_default?(false)
    end

    attribute(:datetime, AshPostgres.TimestamptzUsec, public?: true)
    attribute(:score, :integer, public?: true)
    attribute(:limited_score, :integer, public?: true, constraints: [min: 0, max: 100])

    attribute(:public, :boolean, public?: true)
    attribute(:is_special, :boolean, public?: true, allow_nil?: false, default: true)
    attribute(:category, CiCategory, public?: true)
    attribute(:type, :atom, default: :sponsored, writable?: false, public?: false)
    attribute(:price, :integer, public?: true)
    attribute(:decimal, :decimal, default: Decimal.new(0), public?: true)
    attribute(:status, AshPostgres.Test.Types.Status, public?: true)
    attribute(:status_enum, AshPostgres.Test.Types.StatusEnum, public?: true)
    attribute(:metadata, :map)

    attribute(:status_enum_no_cast, AshPostgres.Test.Types.StatusEnumNoCast,
      source: :status_enum,
      public?: true
    )

    attribute(:constrained_int, :integer,
      constraints: [min: 1, max: 10],
      default: 2,
      allow_nil?: false,
      public?: true
    )

    attribute(:point, AshPostgres.Test.Point, public?: true)
    attribute(:composite_point, AshPostgres.Test.CompositePoint, public?: true)
    attribute(:string_point, AshPostgres.Test.StringPoint, public?: true)
    attribute(:person_detail, AshPostgres.Test.PersonDetail, public?: true)
    attribute(:stuff, :map, public?: true)
    attribute(:list_of_stuff, {:array, :map}, public?: true)
    attribute(:uniq_one, :string, public?: true)
    attribute(:uniq_two, :string, public?: true)
    attribute(:uniq_custom_one, :string, public?: true)
    attribute(:uniq_custom_two, :string, public?: true)
    attribute(:uniq_on_upper, :string, public?: true)
    attribute(:uniq_if_contains_foo, :string, public?: true)

    attribute :model, :tuple do
      constraints(
        fields: [
          alpha: [type: :float, description: "The alpha field"],
          beta: [type: :float, description: "The beta field"],
          t: [type: :float, description: "The t field"]
        ]
      )

      default(fn -> {3.0, 3.0, 1.0} end)
    end

    attribute :list_containing_nils, {:array, :string} do
      public?(true)
      constraints(nil_items?: true)
    end

    attribute(:ltree_unescaped, AshPostgres.Ltree,
      constraints: [min_length: 1, max_length: 10],
      public?: true
    )

    attribute(:ltree_escaped, AshPostgres.Ltree, constraints: [escape?: true], public?: true)

    create_timestamp(:created_at, writable?: true, public?: true)

    update_timestamp(:updated_at,
      type: AshPostgres.TimestamptzUsec,
      writable?: true,
      public?: true
    )
  end

  code_interface do
    define(:create, args: [:title])
    define(:get_by_id, action: :read, get_by: [:id])
    define(:increment_score, args: [{:optional, :amount}])
    define(:destroy)
    define(:update_if_author)
    define(:update_constrained_int, args: [:amount])

    define_calculation(:upper_title, args: [:title])
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

    has_many(:posts_with_my_organization_name_as_a_title, __MODULE__) do
      public?(true)
      no_attributes?(true)
      filter(expr(fragment("? = ?", title, parent(organization.name))))
    end

    belongs_to :parent_post, __MODULE__ do
      public?(true)
    end

    belongs_to(:author, AshPostgres.Test.Author) do
      public?(true)
    end

    has_one :author_from_exists, AshPostgres.Test.Author do
      public?(true)
      no_attributes?(true)
      filter(expr(exists(posts, id == parent(parent(id)))))
    end

    has_many :co_author_posts, AshPostgres.Test.CoAuthorPost do
      public?(true)

      destination_attribute(:post_id)
      filter(expr(not is_nil(post.id)))
    end

    many_to_many :co_authors, AshPostgres.Test.Author do
      public?(true)
      join_relationship(:co_author_posts)

      filter(expr(is_nil(parent(co_author_posts.was_cancelled_at))))
    end

    many_to_many :co_authors_unfiltered, AshPostgres.Test.Author do
      public?(true)
      join_relationship(:co_author_posts)
    end

    has_many :posts_with_matching_title, __MODULE__ do
      public?(true)
      no_attributes?(true)
      filter(expr(parent(title) == title and parent(id) != id))
    end

    has_many :posts_with_matching_point, __MODULE__ do
      public?(true)
      no_attributes?(true)
      filter(expr(parent(point) == point and parent(id) != id))
    end

    has_many :posts_with_matching_string_point, __MODULE__ do
      public?(true)
      no_attributes?(true)
      filter(expr(parent(string_point) == string_point and parent(id) != id))
    end

    has_many(:comments, AshPostgres.Test.Comment, destination_attribute: :post_id, public?: true)

    has_one :latest_comment, AshPostgres.Test.Comment do
      sort(created_at: :desc)
      from_many?(true)
      public?(true)
    end

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

    has_many :high_ratings, AshPostgres.Test.Rating do
      public?(true)
      destination_attribute(:resource_id)
      relationship_context(%{data_layer: %{table: "post_ratings"}})
      filter(expr(score > parent(score)))
    end

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

    many_to_many(:linked_multitenant_posts, AshPostgres.MultitenancyTest.Post,
      public?: true,
      through: AshPostgres.MultitenancyTest.CrossTenantPostLink,
      source_attribute_on_join_resource: :source_id,
      destination_attribute_on_join_resource: :dest_id
    )

    many_to_many(:followers, AshPostgres.Test.User,
      public?: true,
      through: AshPostgres.Test.PostFollower,
      source_attribute_on_join_resource: :post_id,
      destination_attribute_on_join_resource: :follower_id,
      read_action: :active
    )

    has_many :active_followers_assoc, AshPostgres.Test.StatefulPostFollower do
      public?(true)
      filter(expr(state == :active))
    end

    many_to_many(:active_followers, AshPostgres.Test.User,
      public?: true,
      through: AshPostgres.Test.StatefulPostFollower,
      join_relationship: :active_followers_assoc,
      source_attribute_on_join_resource: :post_id,
      destination_attribute_on_join_resource: :follower_id
    )

    many_to_many(:first_3_followers, AshPostgres.Test.User,
      public?: true,
      through: AshPostgres.Test.PostFollower,
      join_relationship: :first_three_followers_assoc,
      source_attribute_on_join_resource: :post_id,
      destination_attribute_on_join_resource: :follower_id,
      filter: expr(parent(first_three_followers_assoc.order) <= 3)
    )

    many_to_many(:stateful_followers, AshPostgres.Test.User,
      public?: true,
      through: AshPostgres.Test.StatefulPostFollower,
      source_attribute_on_join_resource: :post_id,
      destination_attribute_on_join_resource: :follower_id,
      read_action: :active
    )

    has_many(:post_followers, AshPostgres.Test.PostFollower)

    many_to_many(:sorted_followers, AshPostgres.Test.User,
      public?: true,
      through: AshPostgres.Test.PostFollower,
      join_relationship: :post_followers,
      source_attribute_on_join_resource: :post_id,
      destination_attribute_on_join_resource: :follower_id,
      sort: [Ash.Sort.expr_sort(parent(post_followers.order), :integer)]
    )

    has_many(:views, AshPostgres.Test.PostView) do
      public?(true)
    end

    has_many(:permalinks, AshPostgres.Test.Permalink)

    belongs_to :db_point, AshPostgres.Test.DbPoint do
      public?(true)
      allow_nil?(true)
      attribute_type(AshPostgres.Test.Point)
    end

    belongs_to :db_string_point, AshPostgres.Test.DbStringPoint do
      public?(true)
      allow_nil?(true)
      attribute_type(AshPostgres.Test.StringPoint)
    end
  end

  validations do
    validate(attribute_does_not_equal(:title, "not allowed"),
      where: [negate(action_is(:dont_validate))]
    )
  end

  calculations do
    calculate :relevance_score,
              :integer,
              expr(
                if fragment(
                     "ts_rank_cd(to_tsvector(?), ?, 32)::float",
                     ^ref(:title),
                     fragment("to_tsquery(?)", ^arg(:query))
                   ) > 0.6 do
                  1
                else
                  2
                end
              ) do
      argument(:query, :string)
    end

    calculate(:upper_thing, :string, expr(fragment("UPPER(?)", uniq_on_upper)))

    calculate(:upper_title, :string, expr(fragment("UPPER(?)", title)))
    calculate(:title_twice, :string, expr(title <> title))
    calculate(:title_twice_with_calc, :string, TitleTwice)

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

    calculate(:has_author, :boolean, expr(exists(author, true == true)))

    calculate(:has_comments, :boolean, expr(exists(comments, true == true)))

    # DONT DO THIS. USE SOMETHING LIKE `first(comments.name)`
    # We're doing this to test a specific breakage
    calculate(:comment_title, :string, expr(comments.title))

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
      :max_comment_similarity,
      :float,
      expr(max(comments, expr_type: :float, expr: fragment("similarity(?, ?)", title, ^arg(:to))))
    ) do
      argument(:to, :string, allow_nil?: false)
    end

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

    calculate(
      :literal_map_in_expr,
      :map,
      expr(
        cond do
          title == "match" ->
            %{match: true, of: "match"}

          title == "not-match" ->
            %{match: true, of: "not-match"}

          true ->
            %{match: false}
        end
      )
    ) do
      constraints(fields: [match: [type: :boolean], of: [type: :string]])
    end

    calculate :similarity,
              :boolean,
              expr(fragment("(to_tsvector(?) @@ ?)", title, ^arg(:search))) do
      argument(:search, AshPostgres.Tsquery, allow_expr?: true, allow_nil?: false)
    end

    calculate :score_plus, :integer, expr(score + ^arg(:amount)) do
      argument(:amount, :integer, allow_nil?: false)
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

    calculate(
      :start_of_day,
      :datetime,
      expr(start_of_day(fragment("now()"), "EST"))
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
    calculate(:author_first_name_ref_agg_calc, :string, expr(author_first_name))

    calculate(:author_profile_description_from_agg, :string, expr(author_profile_description))

    calculate(:latest_comment_title, :string, expr(latest_comment.title), allow_nil?: true)
  end

  aggregates do
    sum(:sum_of_comment_ratings_calc, [:comments, :ratings], :double_score)
    count(:count_of_comments, :comments)

    count :count_of_comments_with_same_name, :comments do
      filter(expr(title == parent(title)))
    end

    count(:count_of_linked_posts, :linked_posts)

    count :count_of_comments_called_match, :comments do
      filter(title: "match")
    end

    exists :has_comment_called_match, :comments do
      filter(title: "match")
    end

    count :count_of_comments_matching_org_name, [
      :posts_with_matching_title,
      :comments
    ] do
      filter(expr(parent(organization.name) == title))
    end

    count(:count_of_comments_containing_title, :comments_containing_title)

    first :first_comment, :comments, :title do
      sort(title: :asc_nils_last)
    end

    first :first_comment_nils_first, :comments, :title do
      sort(title: :asc_nils_first)
    end

    first :first_comment_nils_first_called_stuff, :comments, :title do
      sort(title: :asc_nils_first)
      filter(expr(title == "stuff"))
    end

    first :first_comment_nils_first_include_nil, :comments, :title do
      include_nil?(true)
      sort(title: :asc_nils_first)
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

    list :comment_titles_with_nils, :comments, :title do
      sort(title: :asc_nils_last)
      include_nil?(true)
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

    sum :sum_of_odd_comment_rating_scores, [:comments, :ratings], :score do
      filter(expr(rem(score, 2) == 1))
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
