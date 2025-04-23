defmodule HasNoLinkedPosts do
  @moduledoc false
  use Ash.Resource.Validation

  def atomic(changeset, _opts, context) do
    condition = expr(exists(linked_posts, true))

    [
      {:atomic, [], condition,
       expr(
         error(^Ash.Error.Changes.InvalidChanges, %{
           message: ^context.message || "Post has linked posts"
         })
       )}
    ]
  end
end

defmodule AshPostgres.MultitenancyTest.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  policies do
    policy always() do
      authorize_if(always())
    end

    policy action(:update_with_policy) do
      # this is silly, but we want to force it to make a query
      authorize_if(expr(exists(self, true)))
    end
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

    update(:update_with_policy)

    update :update_if_no_linked_posts do
      validate HasNoLinkedPosts do
        message "Can only update if Post has no linked posts"
      end
    end

    update :update_if_no_linked_posts_non_atomic do
      require_atomic?(false)

      validate HasNoLinkedPosts do
        message "Can only update if Post has no linked posts"
      end
    end
  end

  postgres do
    table "multitenant_posts"
    repo AshPostgres.TestRepo
  end

  multitenancy do
    # Tells the resource to use the data layer
    # multitenancy, in this case separate postgres schemas
    strategy(:context)
  end

  relationships do
    belongs_to(:org, AshPostgres.MultitenancyTest.Org) do
      public?(true)
    end

    belongs_to(:user, AshPostgres.MultitenancyTest.User) do
      public?(true)
    end

    has_one(:self, __MODULE__, destination_attribute: :id, source_attribute: :id, public?: true)

    many_to_many :linked_posts, __MODULE__ do
      through(AshPostgres.MultitenancyTest.PostLink)
      source_attribute_on_join_resource(:source_id)
      destination_attribute_on_join_resource(:dest_id)
    end

    # has_many(:non_multitenant_post_links, AshPostgres.MultitenancyTest.NonMultitenantPostLink)

    many_to_many :linked_non_multitenant_posts, AshPostgres.Test.Post do
      through(AshPostgres.MultitenancyTest.NonMultitenantPostLink)
      join_relationship(:non_multitenant_post_links)
      source_attribute_on_join_resource(:source_id)
      destination_attribute_on_join_resource(:dest_id)
    end
  end

  calculations do
    calculate(:last_word, :string, expr(fragment("split_part(?, ' ', -1)", name)))
  end
end
