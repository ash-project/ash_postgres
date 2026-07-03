# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.BulkUpsertParent do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("bulk_upsert_parents")
    repo(AshPostgres.TestRepo)
  end

  actions do
    defaults([:read])

    create :upsert_with_child do
      upsert?(true)
      upsert_identity(:unique_number)
      upsert_fields([:name])

      argument(:child, :map, allow_nil?: true)
      change(manage_relationship(:child, :child, on_no_match: {:create, :create}))

      accept([:number, :name])
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:number, :integer, allow_nil?: false, public?: true)
    attribute(:name, :string, allow_nil?: false, public?: true)
  end

  identities do
    identity(:unique_number, [:number])
  end

  relationships do
    has_one :child, AshPostgres.Test.BulkUpsertChild do
      source_attribute(:id)
      destination_attribute(:parent_id)
    end
  end
end
