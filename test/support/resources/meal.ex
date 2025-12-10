# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Meal do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "meals"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      public?(true)
      allow_nil?(false)
    end
  end

  relationships do
    has_many :meal_items, AshPostgres.Test.MealItem do
      public?(true)
    end
  end

  calculations do
    calculate :allowed_for_user,
              :boolean,
              expr(
                count(meal_items) ==
                  count(meal_items, query: [filter: allowed_for_user(user_id: ^arg(:user_id))])
              ) do
      public?(true)

      argument :user_id, :uuid do
        allow_nil?(false)
      end
    end
  end
end
