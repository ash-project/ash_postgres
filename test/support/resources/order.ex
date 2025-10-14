# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Order do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("orders")
    repo(AshPostgres.TestRepo)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :destroy, :update])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
  end

  relationships do
    belongs_to :customer, AshPostgres.Test.Customer do
      public?(true)
      allow_nil?(false)
    end

    belongs_to :product, AshPostgres.Test.Product do
      public?(true)
      allow_nil?(false)
    end
  end
end
