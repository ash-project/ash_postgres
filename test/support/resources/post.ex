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
    read :read do
      primary?(true)
    end

    read :paginated do
      pagination(offset?: true, required?: true, countable: true)
    end

    create :create do
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
  end

  relationships do
    has_many(:comments, AshPostgres.Test.Comment, destination_field: :post_id)

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

    list :comment_titles, :comments, :title do
      sort(title: :asc_nils_last)
    end

    sum(:sum_of_comment_likes, :comments, :likes)

    sum :sum_of_comment_likes_called_match, :comments, :likes do
      filter(title: "match")
    end

    count(:count_of_comment_ratings, [:comments, :ratings])
  end
end
