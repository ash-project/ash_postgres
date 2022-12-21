defmodule AshPostgres.Functions.ILike do
  @moduledoc """
  Maps to the builtin postgres function `ilike`.
  """

  use Ash.Query.Function, name: :ilike

  def args, do: [[:string, :string]]
end
