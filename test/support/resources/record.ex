defmodule AshPostgres.Test.Record do
  @moduledoc false

  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  attributes do
    uuid_primary_key(:id)

    attribute(:full_name, :string, allow_nil?: false, public?: true)

    timestamps(public?: true)
  end

  relationships do
    has_one :entity, AshPostgres.Test.Entity do
      public?(true)
      no_attributes?(true)

      read_action(:read_from_temp)

      filter(expr(full_name == parent(full_name)))
    end

    has_one :temp_entity, AshPostgres.Test.TempEntity do
      public?(true)
      source_attribute(:full_name)
      destination_attribute(:full_name)
    end

    many_to_many :temp_entities, AshPostgres.Test.TempEntity do
      public?(true)

      through(AshPostgres.Test.RecordTempEntity)
    end
  end

  postgres do
    table "records"
    repo AshPostgres.TestRepo
  end

  calculations do
    calculate(
      :temp_entity_full_name,
      :string,
      expr(fragment("coalesce(?, '')", temp_entities.full_name))
    )
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update])
  end
end
