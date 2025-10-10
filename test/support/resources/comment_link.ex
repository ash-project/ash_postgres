# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.CommentLink do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "comment_links"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  identities do
    identity(:unique_link, [:source_id, :dest_id])
  end

  relationships do
    belongs_to :source, AshPostgres.Test.Comment do
      public?(true)
      allow_nil?(false)
      primary_key?(true)
    end

    belongs_to :dest, AshPostgres.Test.Comment do
      public?(true)
      allow_nil?(false)
      primary_key?(true)
    end
  end
end
