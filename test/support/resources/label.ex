# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Label do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id)

    attribute(:value, :string, allow_nil?: false, public?: true)
  end

  postgres do
    table "labels"
    repo AshPostgres.TestRepo

    references do
      polymorphic_on_delete :delete
    end
  end

  actions do
    default_accept(:*)
    defaults([:create, :update, :read, :destroy])
  end

  identities do
    identity(:unique_value, [:value])
  end
end
