# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Yugabyte.Item do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Yugabyte.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo AshPostgres.Yugabyte.Repo
    table "items"
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:key, :string, public?: true, allow_nil?: false)
    attribute(:value, :string, public?: true)
    attribute(:score, :integer, public?: true, default: 0)
  end

  identities do
    identity(:unique_key, [:key])
  end
end
