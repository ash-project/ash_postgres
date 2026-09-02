# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.TwoHopExistsTest.Item do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("two_hop_items")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  relationships do
    belongs_to(:bucket, AshPostgres.Test.TwoHopExistsTest.Bucket,
      public?: true,
      attribute_writable?: true
    )

    # Used for the single-hop comparison aggregates on Entry
    belongs_to(:entry, AshPostgres.Test.TwoHopExistsTest.Entry,
      public?: true,
      attribute_writable?: true
    )

    # on: true join — exercises exists paths whose hops are not FK-joined
    has_many :any_entries, AshPostgres.Test.TwoHopExistsTest.Entry do
      public?(true)
      no_attributes?(true)
    end
  end
end
