# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.User do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
    attribute(:org_id, :uuid, public?: true)
  end

  postgres do
    table "users"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  multitenancy do
    # Tells the resource to use the data layer
    # multitenancy, in this case separate postgres schemas
    strategy(:attribute)
    attribute(:org_id)
    parse_attribute({__MODULE__, :parse_tenant, []})
    global?(true)
  end

  relationships do
    belongs_to(:org, AshPostgres.MultitenancyTest.Org) do
      public?(true)
    end

    has_many :posts, AshPostgres.MultitenancyTest.Post do
      public?(true)
    end
  end

  aggregates do
    list(:years_visited, :posts, :last_word)
    count(:count_visited, :posts)

    # Bypass aggregates for testing context multitenancy
    count :posts_count_all_tenants, :posts do
      public?(true)
      multitenancy :bypass
    end

    count :posts_count_current_tenant, :posts do
      public?(true)
    end

    list :post_names_all_tenants, :posts, :name do
      public?(true)
      multitenancy :bypass
    end

    list :post_names_current_tenant, :posts, :name do
      public?(true)
    end

    exists :has_posts_all_tenants, :posts do
      public?(true)
      multitenancy :bypass
    end

    exists :has_posts_current_tenant, :posts do
      public?(true)
    end

    # SUM aggregates
    sum :total_score_all_tenants, :posts, :score do
      public?(true)
      multitenancy :bypass
    end

    sum :total_score_current_tenant, :posts, :score do
      public?(true)
    end

    # AVG aggregates
    avg :avg_score_all_tenants, :posts, :score do
      public?(true)
      multitenancy :bypass
    end

    avg :avg_score_current_tenant, :posts, :score do
      public?(true)
    end

    # MAX aggregates
    max :max_score_all_tenants, :posts, :score do
      public?(true)
      multitenancy :bypass
    end

    max :max_score_current_tenant, :posts, :score do
      public?(true)
    end

    # MIN aggregates
    min :min_score_all_tenants, :posts, :score do
      public?(true)
      multitenancy :bypass
    end

    min :min_score_current_tenant, :posts, :score do
      public?(true)
    end

    # FIRST aggregates
    first :first_post_name_all_tenants, :posts, :name do
      public?(true)
      multitenancy :bypass
    end

    first :first_post_name_current_tenant, :posts, :name do
      public?(true)
    end
  end

  def parse_tenant("org_" <> id), do: id
end
