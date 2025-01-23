defmodule AshPostgres.Test.Content do
  @moduledoc false
  use Ash.Resource,
    otp_app: :ash_postgres,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "content"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)

    timestamps()
  end

  relationships do
    belongs_to(:note, AshPostgres.Test.Note)

    many_to_many :visibility_groups, AshPostgres.Test.StaffGroup do
      through(AshPostgres.Test.ContentVisibilityGroup)
    end
  end

  aggregates do
    list :visibility_group_staff_ids, [:visibility_groups, :members], :id do
      uniq?(true)
    end
  end
end
