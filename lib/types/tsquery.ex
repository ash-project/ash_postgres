defmodule AshPostgres.Tsquery do
  @moduledoc """
  A thin wrapper around `:string` for working with tsquery types in calculations.

  A calculation of this type cannot be selected, but may be used in calculations.
  """

  use Ash.Type.NewType, subtype_of: :term

  @impl true
  def storage_type(_), do: :tsquery
end
