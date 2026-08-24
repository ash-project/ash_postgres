# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.BulkUpsertChild do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("bulk_upsert_children")
    repo(AshPostgres.TestRepo)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:number])
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:number, :integer, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to :parent, AshPostgres.Test.BulkUpsertParent do
      allow_nil?(false)
    end
  end
end
