# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Product do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("products")
    repo(AshPostgres.TestRepo)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :destroy, :update])
  end

  # This preparation reproduces the bug described in:
  # https://github.com/ash-project/ash_sql/issues/172#issuecomment-3264660128
  preparations do
    prepare(build(sort: [:id]))
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
  end

  relationships do
    has_many :orders, AshPostgres.Test.Order do
      public?(true)
    end
  end
end
