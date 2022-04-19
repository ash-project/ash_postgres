defmodule AshPostgres.Test.Bio do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    attribute(:title, :string)
    attribute(:bio, :string)
  end
end
