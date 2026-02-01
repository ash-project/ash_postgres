# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.FoodItem do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "food_items"
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

    attribute :food_category_id, :uuid do
      public?(true)
      allow_nil?(false)
    end
  end

  relationships do
    belongs_to :category, AshPostgres.Test.FoodCategory do
      source_attribute(:food_category_id)
      public?(true)
      allow_nil?(false)
    end
  end

  calculations do
    calculate :allowed_for_user,
              :boolean,
              expr(
                not exists(
                  AshPostgres.Test.UserExcludedCategory,
                  user_id == ^arg(:user_id) and
                    food_category_id == parent(food_category_id)
                )
              ) do
      public?(true)

      argument :user_id, :uuid do
        allow_nil?(false)
      end
    end
  end
end
