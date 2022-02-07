defmodule AshPostgres.Test.Bio do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:title, :string)
    attribute(:bio, :string)
  end
end
