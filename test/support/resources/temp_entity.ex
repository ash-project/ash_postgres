# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.TempEntity do
  @moduledoc false

  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id)

    attribute(:full_name, :string, allow_nil?: false, public?: true)

    timestamps(public?: true)
  end

  postgres do
    table "temp_entities"
    schema "temp"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read])
  end
end
