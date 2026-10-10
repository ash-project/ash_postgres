# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.SourcedFkChild do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)

    defaults([:create, :read])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :parent_ref, :uuid do
      allow_nil?(false)
      public?(true)
      source(:ref_parent)
    end
  end

  relationships do
    belongs_to :parent, AshPostgres.Test.SourcedFkParent do
      source_attribute(:parent_ref)
      define_attribute?(false)
      public?(true)
    end
  end

  postgres do
    table "sourced_fk_children"
    repo AshPostgres.TestRepo

    references do
      reference :parent, on_delete: :restrict
    end
  end
end
