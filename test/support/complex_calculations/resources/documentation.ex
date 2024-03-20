defmodule AshPostgres.Test.ComplexCalculations.Documentation do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.ComplexCalculations.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept :*

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)

    attribute(
      :status,
      :atom,
      constraints: [
        one_of: [:demonstrated, :performed, :approved, :reopened]
      ],
      allow_nil?: false
    )

    attribute(:documented_at, :utc_datetime_usec)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  calculations do
    calculate(
      :timestamp,
      :utc_datetime_usec,
      expr(
        if is_nil(documented_at) do
          inserted_at
        else
          documented_at
        end
      )
    )
  end

  postgres do
    table "complex_calculations_documentations"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to(:skill, AshPostgres.Test.ComplexCalculations.Skill)
  end
end
