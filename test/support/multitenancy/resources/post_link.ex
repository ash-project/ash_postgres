# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MultitenancyTest.PostLink do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "friend_links"
    repo AshPostgres.TestRepo
  end

  multitenancy do
    strategy(:context)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  relationships do
    belongs_to(:source, AshPostgres.MultitenancyTest.Post,
      primary_key?: true,
      allow_nil?: false
    )

    belongs_to(:dest, AshPostgres.MultitenancyTest.Post,
      primary_key?: true,
      allow_nil?: false
    )
  end
end
