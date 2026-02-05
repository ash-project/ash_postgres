# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Through.School do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "schools"
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

    has_many :teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:classrooms, :classroom_teachers, :teacher])
    end

    has_many :retired_teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:classrooms, :retired_teachers])
    end

    has_many :active_teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:classrooms, :active_teacher])
    end
  end
end
