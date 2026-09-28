# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.Shift do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("shift")
    repo(AshPostgres.TestRepo)
  end

  temporal do
    strategy(:context)
    attribute(:valid_during)
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:holder, :string, public?: true)

    attribute(:valid_during, Ash.Type.Range,
      allow_nil?: false,
      public?: true,
      constraints: [
        inner_type: :naive_datetime,
        lower: [inclusive?: true],
        upper: [inclusive?: false]
      ]
    )
  end

  actions do
    defaults([:read, :destroy, create: [:id, :holder], update: [:holder]])

    create :upsert do
      accept([:id, :holder])
      upsert?(true)
    end
  end
end
