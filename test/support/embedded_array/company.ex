# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.EmbeddedArray.Company do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("embedded_array_companies")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :name, :string, public?: true
  end

  actions do
    default_accept :*
    defaults [:read, :destroy, create: :*, update: :*]
  end

  relationships do
    has_many :estimates, AshPostgres.Test.EmbeddedArray.Estimate do
      public? true
      destination_attribute :company_id
    end
  end
end
