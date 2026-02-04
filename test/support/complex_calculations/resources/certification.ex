# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ComplexCalculations.Certification do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.ComplexCalculations.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  aggregates do
    count :count_of_documented_skills, :skills do
      filter(expr(removed == false and status != :pending))
    end

    count :count_of_approved_skills, :skills do
      filter(expr(removed == false and status == :approved))
    end

    count :count_of_skills, :skills do
      filter(expr(removed == false))
    end

    sum :count_of_skills_ever_demonstrated,
        :skills,
        :count_ever_demonstrated do
      filter(expr(removed == false))
      public?(true)
    end
  end

  attributes do
    uuid_primary_key(:id)
  end

  calculations do
    calculate :all_documentation_approved, :boolean do
      calculation(expr(count_of_skills == count_of_approved_skills))
    end

    calculate :some_documentation_created, :boolean do
      calculation(expr(count_of_documented_skills > 0 && all_documentation_approved == false))
    end
  end

  postgres do
    table "complex_calculations_certifications"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    has_many(:skills, AshPostgres.Test.ComplexCalculations.Skill) do
      public?(true)
    end
  end
end
