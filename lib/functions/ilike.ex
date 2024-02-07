defmodule AshPostgres.Functions.ILike do
  @moduledoc """
  Maps to the builtin postgres function `ilike`.
  """

  use Ash.Query.Function, name: :ilike, predicate?: true

  def args, do: [[:string, :string]]
end
