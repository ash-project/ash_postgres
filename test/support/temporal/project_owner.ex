# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.ProjectOwner do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("project_owner")
    repo(AshPostgres.TemporalTestRepo)
  end

  temporal do
    strategy(:context)
    attribute(:valid_at)
  end

  relationships do
    belongs_to :project, AshPostgres.Test.Temporal.Project do
      primary_key?(true)
      allow_nil?(false)
      attribute_type(:integer)
      public?(true)
      temporal_keys({:valid_at, :valid_at})
    end

    belongs_to :person, AshPostgres.Test.Temporal.Person do
      primary_key?(true)
      allow_nil?(false)
      attribute_type(:integer)
      public?(true)
      temporal_keys({:valid_at, nil})
    end
  end

  actions do
    defaults([:read, :destroy, create: [:project_id, :person_id]])
  end
end
