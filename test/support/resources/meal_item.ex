# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.MealItem do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "meal_items"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :meal_id, :uuid do
      public?(true)
      allow_nil?(false)
    end

    attribute :food_item_id, :uuid do
      public?(true)
      allow_nil?(false)
    end
  end

  relationships do
    belongs_to :meal, AshPostgres.Test.Meal do
      public?(true)
      allow_nil?(false)
    end

    belongs_to :food_item, AshPostgres.Test.FoodItem do
      public?(true)
      allow_nil?(false)
    end
  end

  calculations do
    calculate :allowed_for_user,
              :boolean,
              expr(food_item.allowed_for_user(user_id: ^arg(:user_id))) do
      public?(true)

      argument :user_id, :uuid do
        allow_nil?(false)
      end
    end
  end
end
