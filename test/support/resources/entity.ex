defmodule AshPostgres.Test.Entity do
  @moduledoc false

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key :id

    attribute :full_name, :string, allow_nil?: false

    timestamps(private?: false)
  end

  postgres do
    table "entities"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults [:create, :read]

    read :read_from_temp do
      prepare fn query, _ ->
        Ash.Query.set_context(query, %{data_layer: %{table: "temp_entities", schema: "temp"}})
      end
    end
  end
end
