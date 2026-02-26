# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.RollbackChild do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "rollback_children"
    repo AshPostgres.TestRepo

    references do
      reference(:rollback_parent, on_delete: :delete)
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :create])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to :rollback_parent, AshPostgres.Test.RollbackParent do
      attribute_writable?(true)
      public?(true)
    end
  end
end
