defmodule AshPostgres.Test.Support.ComplexCalculations.Folder do
  @moduledoc """
  A tree structure using the ltree type.
  """

  alias AshPostgres.Test.Support.ComplexCalculations.Folder

  use Ash.Resource,
    domain: AshPostgres.Test.ComplexCalculations.Domain,
    data_layer: AshPostgres.DataLayer

  @default_integer_setting 5

  postgres do
    table "complex_calculations_folders"
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:some_integer_setting, :integer,
      public?: true,
      description: "Some setting that can be inherited. No real semantic meaning, just for demo"
    )

    attribute(:level, AshPostgres.Ltree, public?: true)
  end

  actions do
    defaults([:read])
  end

  relationships do
    has_many :ancestors, Folder do
      public?(true)
      no_attributes?(true)

      # use ltree @> operator to get all ancestors
      filter(expr(fragment("? @> ? AND ? < ?", level, parent(level), nlevel, parent(nlevel))))
    end

    has_many :items, AshPostgres.Test.Support.ComplexCalculations.FolderItem do
      public?(true)
    end
  end

  calculations do
    calculate(:nlevel, :integer, expr(fragment("nlevel(?)", level)))

    calculate(
      :effective_integer_setting,
      :integer,
      expr(
        if is_nil(some_integer_setting) do
          # closest ancestor with a non-nil setting, or the default
          first(
            ancestors,
            query: [
              sort: [nlevel: :desc],
              filter: expr(not is_nil(some_integer_setting))
            ],
            field: :some_integer_setting
          ) || @default_integer_setting
        else
          some_integer_setting
        end
      ),
      description: """
      The effective integer setting, inheriting from ancestors if not explicitly set,
      or defaulting to #{@default_integer_setting} if none are set. No real semantic meaning, just for demo
      """
    )
  end
end
