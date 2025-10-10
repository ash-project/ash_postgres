# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Entity do
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
    table "entities"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read])

    read :read_from_temp do
      prepare(fn query, _ ->
        Ash.Query.set_context(query, %{data_layer: %{table: "temp_entities", schema: "temp"}})
      end)
    end
  end
end
