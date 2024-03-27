defmodule AshPostgres.Test.Account do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  aggregates do
    first(:user_is_active, :user, :is_active)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:is_active, :boolean, public?: true)
  end

  calculations do
    calculate(
      :active,
      :boolean,
      expr(is_active && user_is_active),
      load: [:user_is_active]
    )
  end

  postgres do
    table "accounts"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to(:user, AshPostgres.Test.User) do
      public?(true)
    end
  end
end
