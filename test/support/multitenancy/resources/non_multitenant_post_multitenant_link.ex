# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.NonMultitenantPostMultitenantLink do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "non_multitenant_post_multitenant_links"
    repo AshPostgres.TestRepo

    references do
      reference :source, on_delete: :delete, index?: true
      reference :dest, on_delete: :delete, index?: true
    end
  end

  multitenancy do
    strategy(:context)
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  identities do
    identity(:unique_link, [:source_id, :dest_id])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :state, :atom do
      public?(true)
      constraints(one_of: [:active, :archived])
      default(:active)
    end
  end

  relationships do
    belongs_to :source, AshPostgres.MultitenancyTest.Post do
      public?(true)
      allow_nil?(false)
    end

    belongs_to :dest, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
    end
  end
end
