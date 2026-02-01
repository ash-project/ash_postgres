# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.StatefulPostFollower do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "stateful_post_followers"
    repo AshPostgres.TestRepo
  end

  identities do
    identity(:join_attributes, [:post_id, :follower_id, :state])
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:order, :integer, public?: true)

    attribute :state, :atom do
      public?(true)
      constraints(one_of: [:active, :inactive])
      default(:active)
    end
  end

  relationships do
    belongs_to :post, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
    end

    belongs_to :follower, AshPostgres.Test.User do
      public?(true)
      allow_nil?(false)
    end
  end
end
