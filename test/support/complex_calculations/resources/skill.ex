defmodule AshPostgres.Test.ComplexCalculations.Skill do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.ComplexCalculations.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  aggregates do
    first :latest_documentation_status, [:documentations], :status do
      sort(timestamp: :desc)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:removed, :boolean, default: false, allow_nil?: false, public?: true)
  end

  calculations do
    calculate :status, :atom do
      calculation(
        expr(
          if is_nil(latest_documentation_status) do
            :pending
          else
            latest_documentation_status
          end
        )
      )
    end
  end

  postgres do
    table "complex_calculations_skills"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to(:certification, AshPostgres.Test.ComplexCalculations.Certification) do
      public?(true)
    end

    has_many :documentations, AshPostgres.Test.ComplexCalculations.Documentation do
      public?(true)
      sort(timestamp: :desc, inserted_at: :desc)
    end

    has_one :latest_documentation, AshPostgres.Test.ComplexCalculations.Documentation do
      public?(true)
      sort(timestamp: :desc, inserted_at: :desc)
    end
  end
end
