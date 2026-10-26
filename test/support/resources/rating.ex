# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Rating do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    polymorphic?(true)
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:score, :integer, public?: true)
    attribute(:resource_id, :uuid, public?: true)
    attribute(:external_id, :string, public?: true)
  end

  identities do
    identity(:unique_external_id, [:resource_id, :external_id], field_names: [:external_id])
  end

  calculations do
    calculate(:double_score, :integer, expr(score * 2))
  end
end
