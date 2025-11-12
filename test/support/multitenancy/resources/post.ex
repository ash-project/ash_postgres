# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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
    attribute(:score, :integer, public?: true)
    attribute(:rating, :decimal, public?: true)
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

    update(:update_with_policy)
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

    has_many :non_multitenant_post_multitenant_links,
             AshPostgres.MultitenancyTest.NonMultitenantPostMultitenantLink do
      destination_attribute(:source_id)
    end

    many_to_many :linked_non_multitenant_posts, AshPostgres.Test.Post do
      through(AshPostgres.MultitenancyTest.NonMultitenantPostLink)
      join_relationship(:non_multitenant_post_links)
      source_attribute_on_join_resource(:source_id)
      destination_attribute_on_join_resource(:dest_id)
    end

    many_to_many :linked_non_multitenant_posts_through_multitenant_link, AshPostgres.Test.Post do
      through(AshPostgres.MultitenancyTest.NonMultitenantPostMultitenantLink)
      join_relationship(:non_multitenant_post_links_through_multitenant_link)
      source_attribute_on_join_resource(:source_id)
      destination_attribute_on_join_resource(:dest_id)
    end
  end

  calculations do
    calculate(:last_word, :string, expr(fragment("split_part(?, ' ', -1)", name)))
  end

  aggregates do
    # COUNT Aggregates WITH bypass for context multitenancy
    count :total_linked_posts_all_tenants, :linked_posts do
      public?(true)
      multitenancy :bypass
    end

    # COUNT Aggregates WITHOUT bypass for context multitenancy
    count :total_linked_posts_current_tenant, :linked_posts do
      public?(true)
    end

    # EXISTS Aggregate WITH bypass
    exists :has_linked_posts_all_tenants, :linked_posts do
      public?(true)
      multitenancy :bypass
    end

    # EXISTS Aggregate WITHOUT bypass
    exists :has_linked_posts_current_tenant, :linked_posts do
      public?(true)
    end
  end
end
