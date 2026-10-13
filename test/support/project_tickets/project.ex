# SPDX-FileCopyrightText: 2026 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ProjectTickets.Project do
  @moduledoc false
  use Ash.Resource, domain: AshPostgres.Test.Domain, data_layer: AshPostgres.DataLayer

  postgres do
    table "ticket_projects"
    repo AshPostgres.TestRepo
  end

  attributes do
    integer_primary_key(:id, writable?: true)
  end

  relationships do
    has_many(:tickets, AshPostgres.Test.ProjectTickets.Ticket, public?: true)
  end

  actions do
    defaults([:read, create: [:id]])
  end
end
