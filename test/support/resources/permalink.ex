# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Permalink do
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
  end

  relationships do
    belongs_to :post, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
      attribute_writable?(true)
    end
  end

  postgres do
    table "post_permalinks"
    repo AshPostgres.TestRepo

    references do
      reference :post, on_delete: :nothing
    end
  end
end
