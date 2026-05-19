# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.EmbeddedArray.Estimate do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshPostgres.Test.EmbeddedArray.Option

  postgres do
    table("embedded_array_estimates")
    repo(AshPostgres.TestRepo)

    migration_types options: :jsonb
    storage_types options: :jsonb
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :title, :string, public?: true
    attribute :active, :boolean, public?: true, default: true
    attribute :options, {:array, Option}, public?: true
    attribute :company_id, :uuid, public?: true
  end

  actions do
    default_accept :*
    defaults [:read, :destroy, create: :*, update: :*]
  end

  relationships do
    belongs_to :company, AshPostgres.Test.EmbeddedArray.Company do
      public? true
    end
  end
end
