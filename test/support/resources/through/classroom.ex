# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Through.Classroom do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "classrooms"
    repo AshPostgres.TestRepo
  end

  policies do
    policy action_type(:read) do
      authorize_if(expr(public == true))
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
    attribute(:public, :boolean, public?: true, default: true)
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, create: :*, update: :*])
  end

  relationships do
    belongs_to :school, AshPostgres.Test.Through.School do
      public?(true)
    end

    has_many :classroom_teachers, AshPostgres.Test.Through.ClassroomTeacher do
      public?(true)
    end

    has_many :retired_classroom_teachers, AshPostgres.Test.Through.ClassroomTeacher do
      public?(true)
      filter(expr(not is_nil(retired_at)))
    end

    has_many :students, AshPostgres.Test.Through.Student do
      public?(true)
    end

    has_many :retired_teachers, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:retired_classroom_teachers, :teacher])
    end

    has_one :active_classroom_teacher, AshPostgres.Test.Through.ClassroomTeacher do
      public?(true)
      from_many?(true)
      filter(expr(is_nil(retired_at)))
    end

    has_one :active_teacher, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:active_classroom_teacher, :teacher])
    end
  end
end
