# SPDX-FileCopyrightText: 2026 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ProjectTickets.Comment do
  @moduledoc false
  use Ash.Resource, domain: AshPostgres.Test.Domain, data_layer: AshPostgres.DataLayer

  postgres do
    table "project_ticket_comments"
    repo AshPostgres.TestRepo
  end

  attributes do
    integer_primary_key(:id, writable?: true)
    attribute(:ticket_id, :integer, public?: true)
  end

  actions do
    defaults([:read, create: [:id, :ticket_id]])
  end
end
