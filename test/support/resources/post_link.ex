# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.PostLink do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "post_links"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  identities do
    identity(:unique_link, [:source_post_id, :destination_post_id])
  end

  attributes do
    attribute :state, :atom do
      public?(true)
      constraints(one_of: [:active, :archived])
      default(:active)
    end
  end

  relationships do
    belongs_to :source_post, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
      primary_key?(true)
    end

    belongs_to :destination_post, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
      primary_key?(true)
    end
  end
end
