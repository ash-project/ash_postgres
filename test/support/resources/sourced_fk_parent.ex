# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.SourcedFkParent do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)

    defaults([:create, :read, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
  end

  relationships do
    has_many :children, AshPostgres.Test.SourcedFkChild do
      destination_attribute(:parent_ref)
    end
  end

  postgres do
    table "sourced_fk_parents"
    repo AshPostgres.TestRepo
  end
end
