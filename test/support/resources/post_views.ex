# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.PostView do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)

    defaults([:create, :read])
  end

  attributes do
    create_timestamp(:time)
    attribute(:browser, :atom, constraints: [one_of: [:firefox, :chrome, :edge]], public?: true)
  end

  relationships do
    belongs_to :post, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(false)
      attribute_writable?(true)
    end
  end

  resource do
    require_primary_key?(false)
  end

  postgres do
    table "post_views"
    repo AshPostgres.TestRepo

    references do
      reference :post, ignore?: true
    end
  end
end
