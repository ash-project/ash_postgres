# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Booking do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("bookings")
    repo(AshPostgres.TestRepo)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)

    attribute(:stay, :range) do
      public?(true)
      constraints(inner_type: :datetime, inner_constraints: [precision: :microsecond])
    end

    attribute(:nights, :range) do
      public?(true)
      constraints(inner_type: :date)
    end

    attribute(:guests, :range) do
      public?(true)
      constraints(inner_type: :integer)
    end
  end
end
