# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.PostFollower do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "post_followers"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    attribute(:order, :integer, public?: true)
  end

  relationships do
    belongs_to :post, AshPostgres.Test.Post do
      primary_key?(true)
      public?(true)
      allow_nil?(false)
    end

    belongs_to :follower, AshPostgres.Test.User do
      primary_key?(true)
      public?(true)
      allow_nil?(false)
    end
  end
end
