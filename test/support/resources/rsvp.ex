# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.RSVP do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "rsvps"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])

    # Uses an expression with an array of atoms for a custom type backed by integers.
    update :clear_response do
      change(
        atomic_update(
          :response,
          expr(
            if response in [:accepted, :declined] do
              :awaiting
            else
              response
            end
          )
        )
      )
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:response, AshPostgres.Test.Types.Response,
      allow_nil?: false,
      public?: true,
      default: 0
    )
  end
end
