defmodule AshPostgres.Test.Record do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :full_name, :string, allow_nil?: false

    timestamps(private?: false)
  end

  relationships do
    alias AshPostgres.Test.Entity

    has_one :entity, Entity do
      no_attributes? true

      read_action :read_from_temp

      filter expr(full_name == parent(full_name))
    end
  end

  postgres do
    table "records"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults [:create, :read]
  end
end
