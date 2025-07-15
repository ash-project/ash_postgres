defmodule AshPostgres.Test.Support.ComplexCalculations.FolderItem do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.ComplexCalculations.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "complex_calculations_folder_items"
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)

    attribute(:level, :integer,
      public?: true,
      description: """
      No real semantic meaning here, just for demo, this *deliberately* is named the same as the ltree level column in Folder,
      but is NOT related to it in any way
      """
    )
  end

  actions do
    defaults([:read])
  end

  calculations do
    calculate(:folder_setting, :integer, expr(folder.effective_integer_setting))
  end

  relationships do
    belongs_to(:folder, AshPostgres.Test.Support.ComplexCalculations.Folder) do
      public?(true)
    end
  end
end
