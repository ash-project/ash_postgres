defmodule AshPostgres.Test.Types.StatusEnumNoCast do
  @moduledoc false
  use Ash.Type.Enum, values: [:open, :closed]

  def storage_type, do: :status

  def cast_in_query?, do: false
end
