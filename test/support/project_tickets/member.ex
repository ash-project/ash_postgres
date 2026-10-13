# SPDX-FileCopyrightText: 2026 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ProjectTickets.Member do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "project_ticket_members"
    repo AshPostgres.TestRepo
  end

  attributes do
    integer_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
    attribute(:hidden, :boolean, public?: true, default: false)
  end

  actions do
    defaults([:read, create: [:id, :name, :hidden]])
  end

  policies do
    policy action_type(:read) do
      authorize_if(expr(hidden == false))
    end
  end
end
