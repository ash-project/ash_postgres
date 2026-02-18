# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Item do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    primary_read_warning?: false

  postgres do
    table "items"
    repo AshPostgres.TestRepo
  end

  preparations do
    prepare(build(sort: [id: :asc]))
  end

  actions do
    defaults(create: :*)

    read :read_active do
      primary?(true)
      filter(expr(active == true))
    end

    read :read_all do
      # No filter - returns all records
    end
  end

  attributes do
    uuid_v7_primary_key(:id)
    attribute(:name, :string, public?: true)
    attribute(:active, :boolean, public?: true, default: false)
  end

  relationships do
    belongs_to :container, AshPostgres.Test.Container do
      public?(true)
      allow_nil?(false)
    end
  end
end
