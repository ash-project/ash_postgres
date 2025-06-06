defmodule AshPostgres.Test.RecordTempEntity do
  @moduledoc false

  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "records_temp_entities"
    repo AshPostgres.TestRepo
  end

  attributes do
    uuid_primary_key(:id)
  end

  relationships do
    belongs_to(:record, AshPostgres.Test.Record, public?: true)
    belongs_to(:temp_entity, AshPostgres.Test.TempEntity, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
