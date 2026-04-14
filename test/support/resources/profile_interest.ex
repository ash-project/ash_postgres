# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ProfileInterest do
  @moduledoc """
  A join table in the "profiles" schema linking Profile to Interest.

  This tests cross-schema many_to_many relationships between two custom schemas:
  - Profile is in "profiles" schema
  - Interest is in "interest" schema
  - ProfileInterest (this resource) is in "profiles" schema
  """
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "profile_interests"
    schema "profiles"
    repo AshPostgres.TestRepo
  end

  attributes do
    uuid_primary_key(:id)
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, create: :*, update: :*])
  end

  relationships do
    belongs_to :profile, AshPostgres.Test.Profile do
      public?(true)
      allow_nil?(false)
    end

    belongs_to :interest, AshPostgres.Test.Interest do
      public?(true)
      allow_nil?(false)
    end
  end

  identities do
    identity(:unique_profile_interest, [:profile_id, :interest_id])
  end
end
