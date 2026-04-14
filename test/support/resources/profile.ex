# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Profile do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("profile")
    schema("profiles")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:description, :string, public?: true)
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

    read :by_indirectly_matching_description do
      argument :term, :string do
        allow_nil?(false)
      end

      filter(expr(calc_word_similarity(term: ^arg(:term)) > 0.2))
    end

    read :by_directly_matching_description do
      argument :term, :string do
        allow_nil?(false)
      end

      filter(expr(trigram_word_similarity(description, ^arg(:term)) > 0.2))
    end
  end

  calculations do
    calculate :calc_word_similarity,
              :float,
              expr(trigram_word_similarity(description, ^arg(:term))) do
      argument(:term, :string, allow_nil?: false)
    end
  end

  relationships do
    belongs_to(:author, AshPostgres.Test.Author) do
      public?(true)
    end

    # Cross-schema many_to_many: Profile (profiles schema) -> Interest (public schema)
    # through ProfileInterest (profiles schema)
    many_to_many :interests, AshPostgres.Test.Interest do
      public?(true)
      through(AshPostgres.Test.ProfileInterest)
      source_attribute_on_join_resource(:profile_id)
      destination_attribute_on_join_resource(:interest_id)
    end
  end
end
