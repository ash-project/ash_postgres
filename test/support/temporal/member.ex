# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.Member do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("member")
    repo(AshPostgres.TestRepo)
  end

  temporal do
    strategy(:context)
    attribute(:valid_at)
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:email, :ci_string, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: [:id, :email], update: [:email]])
  end

  identities do
    identity(:unique_email, [:email])
  end
end
