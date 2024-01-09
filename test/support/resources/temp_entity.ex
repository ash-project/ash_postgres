defmodule AshPostgres.Test.TempEntity do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :full_name, :string, allow_nil?: false

    timestamps(private?: false)
  end

  postgres do
    table "temp_entities"
    schema "temp"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults [:create, :read]
  end
end
