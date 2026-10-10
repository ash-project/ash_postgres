# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.ScopedPlan do
  @moduledoc false
  # A temporal resource in a non-default schema: its split writes must target
  # `"temporal_scoped"."scoped_plan"`, not an unqualified table.
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("scoped_plan")
    schema("temporal_scoped")
    repo(AshPostgres.TemporalTestRepo)
  end

  temporal do
    strategy(:context)
    attribute(:valid_at)
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)

    attribute(:valid_at, Ash.Type.Range,
      allow_nil?: false,
      constraints: [
        inner_type: :datetime,
        inner_constraints: [precision: :microsecond],
        lower: [inclusive?: true],
        upper: [inclusive?: false]
      ],
      public?: true
    )
  end

  actions do
    defaults([:read, :destroy, create: [:id, :name]])

    update :rename do
      accept([:name])
    end
  end
end
