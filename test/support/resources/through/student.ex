# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Through.Student do
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
    table "students"
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
    count :retired_teacher_count, [:classroom, :retired_teachers] do
      public?(true)
    end
  end

  relationships do
    belongs_to :classroom, AshPostgres.Test.Through.Classroom do
      public?(true)
      allow_nil?(false)
    end

    has_one :teacher, AshPostgres.Test.Through.Teacher do
      public?(true)
      through([:classroom, :active_teacher])
    end
  end
end
