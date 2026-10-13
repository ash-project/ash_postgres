# SPDX-FileCopyrightText: 2026 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ProjectTickets.Ticket do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "project_tickets"
    repo AshPostgres.TestRepo
  end

  attributes do
    integer_primary_key(:id, writable?: true)
    attribute(:hours, :integer, public?: true)
    attribute(:owner_id, :integer, public?: true)
    attribute(:project_id, :integer, public?: true)
  end

  relationships do
    belongs_to(:assignee, AshPostgres.Test.ProjectTickets.Member,
      public?: true,
      attribute_type: :integer
    )

    has_many(:comments, AshPostgres.Test.ProjectTickets.Comment, public?: true)
  end

  aggregates do
    first(:assignee_name, :assignee, :name, public?: true)
    count(:comment_count, :comments, public?: true)
  end

  actions do
    defaults(create: [:id, :hours, :owner_id, :project_id, :assignee_id])

    read :read do
      primary?(true)
      pagination(offset?: true, countable: true, required?: false)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end
  end

  field_policies do
    field_policy :hours do
      authorize_if(expr(owner_id == ^actor(:id)))
    end

    field_policy :* do
      authorize_if(always())
    end
  end
end
