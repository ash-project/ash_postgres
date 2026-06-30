# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.Tier do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("tier")
    repo(AshPostgres.TestRepo)
  end

  temporal do
    strategy(:context)
    attribute(:valid_at)
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)

    attribute(:valid_at, Ash.Type.Range,
      constraints: [inner_type: :datetime, inner_constraints: [precision: :microsecond]],
      public?: true
    )
  end

  relationships do
    has_many :subscriptions, AshPostgres.Test.Temporal.Subscription do
      public?(true)
      no_attributes?(true)
      filter(expr(tier_id == parent(id)))
      temporal_keys({:valid_at, :valid_at})
    end
  end

  aggregates do
    count(:subscription_count, :subscriptions)
  end

  actions do
    # `valid_at` is derived from `as_of`, never accepted as input.
    defaults([:read, create: [:id, :name]])

    # Ends the tier's validity AND cascades to its subscriptions. `after_action?: false`
    # runs the cascade BEFORE the parent destroy (child-first) so children are truncated
    # at `as_of` first — otherwise truncating the parent would orphan them (the PERIOD FK
    # only supports NO ACTION, checked per statement).
    destroy :archive do
      require_atomic?(false)
      change(cascade_destroy(:subscriptions, after_action?: false))
    end
  end
end
