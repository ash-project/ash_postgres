defmodule AshPostgres.Test.Bio do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    attribute(:title, :string)
    attribute(:bio, :string)
    attribute(:years_of_experience, :integer)

    attribute :list_of_strings, {:array, :string} do
      allow_nil?(true)
      default(nil)
    end
  end
end
