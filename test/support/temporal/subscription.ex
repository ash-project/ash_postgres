# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.Subscription do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("subscription")
    repo(AshPostgres.TestRepo)
  end

  temporal do
    strategy(:context)
    attribute(:valid_at)
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:tier, :string, public?: true)
    attribute(:tier_id, :integer, public?: true)
    attribute(:seats, :integer, default: 0, public?: true)
    attribute(:activated_at, :utc_datetime_usec, public?: true)

    attribute(:valid_at, Ash.Type.Range,
      constraints: [inner_type: :datetime, inner_constraints: [precision: :microsecond]],
      public?: true
    )
  end

  relationships do
    belongs_to :tier_record, AshPostgres.Test.Temporal.Tier do
      source_attribute(:tier_id)
      destination_attribute(:id)
      define_attribute?(false)
      attribute_type(:integer)
      temporal_keys({:valid_at, :valid_at})
      public?(true)
    end
  end

  aggregates do
    # Aggregate *through* the temporal PERIOD-FK relationship — its join carries the
    # baked `range_overlaps(parent(valid_at), valid_at)` filter, so this exercises
    # `range_overlaps` rendering + `as_of` anchoring on an aggregate sort.
    first(:tier_name, :tier_record, :name)
  end

  actions do
    defaults([
      :read,
      :destroy,
      # `valid_at` is never accepted as input — a temporal write sets `[as_of, ∞)`.
      create: [:id, :tier, :tier_id, :seats, :activated_at]
    ])

    # Creates the subscription AND its tier via manage_relationship — used to check the
    # parent's `as_of` threads down to the managed child (the PERIOD FK would reject a
    # child created at a different instant than the parent's historical period).
    create :create_with_tier do
      accept([:id, :tier, :seats])
      argument(:new_tier, :map, allow_nil?: false)

      change(
        manage_relationship(:new_tier, :tier_record, on_no_match: :create, on_match: :ignore)
      )
    end

    update :change_tier do
      require_atomic?(true)
      accept([:tier])
    end

    # Non-atomic update — exercises the single-row `update/2` data layer path.
    update :change_tier_nonatomic do
      require_atomic?(false)
      accept([:tier])
    end

    # Atomic arithmetic update — exercised over FOR PORTION OF.
    update :add_seat do
      require_atomic?(true)
      change(atomic_update(:seats, expr(seats + 1)))
    end

    # Atomic validation that references `now()`; must be evaluated at the
    # changeset's `as_of` rather than the wall clock.
    update :validated_touch do
      require_atomic?(true)
      validate({AshPostgres.Test.Temporal.BeforeNow, field: :activated_at})
      change(atomic_update(:seats, expr(seats + 1)))
    end

    destroy :expire do
      require_atomic?(true)
    end
  end
end
