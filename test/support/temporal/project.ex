# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.Project do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("project")
    repo(AshPostgres.TemporalTestRepo)
  end

  temporal do
    strategy(:context)
    attribute(:valid_at)
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)
  end

  relationships do
    # Both sides are temporal, so the join's filter carries
    # `range_overlaps(parent(valid_at), valid_at)`.
    has_many :owner_links, AshPostgres.Test.Temporal.ProjectOwner do
      public?(true)
      temporal_keys({:valid_at, :valid_at})
    end

    many_to_many :owners, AshPostgres.Test.Temporal.Person do
      public?(true)
      through(AshPostgres.Test.Temporal.ProjectOwner)
      join_relationship(:owner_links)
      source_attribute_on_join_resource(:project_id)
      destination_attribute_on_join_resource(:person_id)
    end

    has_many :owner_people, AshPostgres.Test.Temporal.Person do
      public?(true)
      through([:owner_links, :person])
      temporal_keys({:valid_at, nil})
    end
  end

  actions do
    defaults([:read, create: [:id, :name]])

    update :set_owners do
      require_atomic?(false)
      argument(:owner_ids, {:array, :integer}, allow_nil?: false)
      change(manage_relationship(:owner_ids, :owners, type: :append_and_remove))
    end
  end
end
