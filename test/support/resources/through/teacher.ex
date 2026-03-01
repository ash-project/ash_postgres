# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Through.Teacher do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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

  postgres do
    table "teachers"
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
    has_many :classroom_teachers, AshPostgres.Test.Through.ClassroomTeacher do
      public?(true)
    end

    has_many :classrooms, AshPostgres.Test.Through.Classroom do
      public?(true)
      through([:classroom_teachers, :classroom])
    end
  end
end
