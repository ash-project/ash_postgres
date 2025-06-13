defmodule AshPostgres.Test.ComplexCalculations.Documentation do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.ComplexCalculations.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)

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
      public?: true,
      allow_nil?: false
    )

    attribute(:documented_at, :utc_datetime_usec, public?: true)
    create_timestamp(:inserted_at, public?: true, writable?: true)
    update_timestamp(:updated_at, public?: true, writable?: true)
  end

  calculations do
    calculate(:custom_map, :map, expr(%{status: status, two: "Two"}))

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

    calculate :is_active_with_timezone, :boolean do
      calculation(expr(inserted_at > lazy({AshPostgres.Test.TimezoneHelper, :seoul_time, []})))
    end
  end

  postgres do
    table "complex_calculations_documentations"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to(:skill, AshPostgres.Test.ComplexCalculations.Skill) do
      public?(true)
    end
  end
end

defmodule AshPostgres.Test.TimezoneHelper do
  @moduledoc false
  def seoul_time do
    # Fixed datetime for testing - equivalent to 2024-05-01 21:00:00 in Seoul (UTC+9)
    ~U[2024-05-01 12:00:00Z] |> DateTime.shift_zone!("Asia/Seoul")
  end
end
