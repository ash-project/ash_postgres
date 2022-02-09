defmodule AshPostgres.Test.Types.StatusEnum do
  @moduledoc false
  use Ash.Type.Enum, values: [:open, :closed]

  def storage_type, do: :status
end
