# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.TwoHopExistsTest.Entry do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("two_hop_entries")
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

    has_many(:direct_items, AshPostgres.Test.TwoHopExistsTest.Item,
      public?: true,
      destination_attribute: :entry_id
    )
  end

  aggregates do
    count(:item_count, [:bucket, :items])
    exists(:has_item_agg?, [:bucket, :items])
    exists(:has_direct_item_agg?, [:direct_items])
    exists(:has_item_entry_agg?, [:bucket, :items, :entry])
    exists(:has_item_any_entry_agg?, [:bucket, :items, :any_entries])
  end

  calculations do
    calculate(:has_item_true?, :boolean, expr(exists(bucket.items, true)))
    calculate(:has_item_id?, :boolean, expr(exists(bucket.items, not is_nil(id))))
    calculate(:has_direct_item_true?, :boolean, expr(exists(direct_items, true)))
    calculate(:has_item_entry_true?, :boolean, expr(exists(bucket.items.entry, true)))

    calculate(
      :has_item_any_entry_true?,
      :boolean,
      expr(exists(bucket.items.any_entries, true))
    )
  end
end
