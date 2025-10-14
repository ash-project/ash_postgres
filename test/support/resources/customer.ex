# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Customer do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("customers")
    repo(AshPostgres.TestRepo)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :destroy, :update])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
  end

  relationships do
    has_many :orders, AshPostgres.Test.Order do
      public?(true)
    end

    # This relationship reproduces the bug described in:
    # https://github.com/ash-project/ash_sql/issues/172#issuecomment-3264660128
    has_many :purchased_products, AshPostgres.Test.Product do
      public?(true)
      no_attributes?(true)
      filter(expr(orders.customer_id == parent(id)))
    end
  end
end
