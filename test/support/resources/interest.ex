# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Interest do
  @moduledoc """
  An interest resource in the "interest" schema (e.g., "sports", "music", "coding").

  Used to test cross-schema many_to_many relationships:
  - Interest lives in "interest" schema
  - Profile lives in "profiles" schema
  - ProfileInterest (join table) lives in "profiles" schema
  """
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "interests"
    schema "interest"
    repo AshPostgres.TestRepo
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, create: :*, update: :*])
  end

  relationships do
    many_to_many :profiles, AshPostgres.Test.Profile do
      public?(true)
      through(AshPostgres.Test.ProfileInterest)
      source_attribute_on_join_resource(:interest_id)
      destination_attribute_on_join_resource(:profile_id)
    end
  end
end
