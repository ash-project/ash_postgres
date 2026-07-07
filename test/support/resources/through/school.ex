# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Through.School do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "schools"
    repo AshPostgres.TestRepo
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end
  end

  field_policies do
    field_policy :* do
      authorize_if(always())
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, create: :*, update: :*])
  end

  aggregates do
    count :classroom_count, :classrooms do
      public?(true)
    end

    count :teacher_count, :teachers do
      public?(true)
    end

    count :teacher_count_via_path, [:classrooms, :classroom_teachers, :teacher] do
      public?(true)
    end

    count :retired_teacher_count, :retired_teachers do
      public?(true)
    end

    count :active_teacher_count, :active_teachers do
      public?(true)
    end
  end

  relationships do
    has_many :classrooms, AshPostgres.Test.Through.Classroom do
      public?(true)
    end

    has_many :context_filtered_classrooms, AshPostgres.Test.Through.Classroom do
      public?(true)

      filter(
        expr(
          is_nil(^context(:sample_context)) or
            name == ^context(:sample_context)
        )
      )
    end

    has_many :actor_filtered_classrooms, AshPostgres.Test.Through.Classroom do
      public?(true)

      filter(expr(name == ^actor(:visible_classroom)))
    end

    has_many :teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:classrooms, :classroom_teachers, :teacher])
    end

    has_many :context_teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:context_filtered_classrooms, :classroom_teachers, :teacher])
    end

    has_many :actor_teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:actor_filtered_classrooms, :classroom_teachers, :teacher])
    end

    has_many :retired_teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:classrooms, :retired_teachers])
    end

    has_many :active_teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:classrooms, :active_teacher])
    end

    # Two-hop `through` relationships that exercise the same template resolution
    # on the intermediate (context/actor filtered) relationship.
    has_many :context_students, AshPostgres.Test.Through.Student do
      public?(true)
      through([:context_filtered_classrooms, :students])
    end

    has_many :actor_students, AshPostgres.Test.Through.Student do
      public?(true)
      through([:actor_filtered_classrooms, :students])
    end
  end
end
