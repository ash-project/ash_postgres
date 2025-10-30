# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.UserExcludedCategory do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "user_excluded_categories"
    repo AshPostgres.TestRepo
  end

  actions do
    default_accept :*
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      public? true
      allow_nil? false
    end

    attribute :food_category_id, :uuid do
      public? true
      allow_nil? false
    end
  end

  relationships do
    belongs_to :food_category, AshPostgres.Test.FoodCategory do
      public? true
      allow_nil? false
    end
  end
end
