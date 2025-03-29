defmodule AshPostgres.Test.CSVColumnMatchingEmbedded do
  @moduledoc false
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute(:column, :integer, allow_nil?: true, public?: true)
    attribute(:attribute, :string, allow_nil?: true, public?: true)
  end
end

defmodule AshPostgres.Test.CSVColumnMappingNewType do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        attribute: [type: :string, allow_nil?: false],
        column: [type: :integer, allow_nil?: false]
      ]
    ]
end

defmodule AshPostgres.Test.CSV do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshPostgres.Test

  actions do
    default_accept(:*)

    defaults([:create, :read, :destroy])

    update :update do
      primary?(true)
      accept([:column_mapping_embedded, :column_mapping_new_type])
      # require_atomic?(false)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:column_mapping_embedded, {:array, Test.CSVColumnMatchingEmbedded}, public?: true)
    attribute(:column_mapping_new_type, {:array, Test.CSVColumnMatchingEmbedded}, public?: true)
  end

  postgres do
    table "csv"
    repo(AshPostgres.TestRepo)

    storage_types column_mapping_embedded: :jsonb, column_mapping_new_type: :jsonb
  end
end
