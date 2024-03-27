defmodule AshPostgres.Tsvector do
  @moduledoc """
  A thin wrapper around `:string` for working with tsvector types in calculations.

  A calculation of this type cannot be selected, but may be used in calculations.
  """

  use Ash.Type.NewType, subtype_of: :term

  @impl true
  def storage_type(_), do: :tsvector
end
