# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.UnrelatedAggregatesTest.Profile do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("unrelated_profiles")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
    attribute(:age, :integer, public?: true)
    attribute(:bio, :string, public?: true)
    attribute(:active, :boolean, default: true, public?: true)
    attribute(:owner_id, :uuid, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  policies do
    # Allow unrestricted access for most tests, but we'll create a SecureProfile for auth tests
    policy action_type([:create, :update, :destroy]) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(always())
    end
  end
end
