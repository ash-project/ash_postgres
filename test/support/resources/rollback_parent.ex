# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.RollbackParent do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "rollback_parents"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:read])

    create :create do
      argument(:children, {:array, :map}, allow_nil?: true)
      change(manage_relationship(:children, type: :create))
    end

    create :upsert do
      upsert?(true)
      upsert_identity(:unique_name)
      upsert_fields([:name])
      argument(:children, {:array, :map}, allow_nil?: true)
      change(manage_relationship(:children, type: :create))
    end

    update :update_with_children do
      require_atomic?(false)
      argument(:children, {:array, :map}, allow_nil?: true)
      change(manage_relationship(:children, type: :create))
    end

    destroy :destroy_with_children do
      require_atomic?(false)
      argument(:children, {:array, :map}, allow_nil?: true)
      change(manage_relationship(:children, type: :create))
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
  end

  identities do
    identity(:unique_name, [:name])
  end

  relationships do
    has_many(:children, AshPostgres.Test.RollbackChild,
      destination_attribute: :rollback_parent_id,
      public?: true
    )
  end
end
