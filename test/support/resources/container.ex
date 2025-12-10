# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Container do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "containers"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:read, create: :*])
  end

  attributes do
    uuid_v7_primary_key(:id)
  end

  calculations do
    calculate(
      :active_item_name,
      :string,
      expr(item_active.name)
    )

    calculate(
      :all_item_name,
      :string,
      expr(item_all.name)
    )
  end

  relationships do
    has_one :item_active, AshPostgres.Test.Item do
      public?(true)
      # Uses primary read action (read_active) which filters active == true
      from_many?(true)
    end

    has_one :item_all, AshPostgres.Test.Item do
      public?(true)
      # Explicitly uses read_all with no filter
      read_action(:read_all)
      from_many?(true)
    end
  end
end
