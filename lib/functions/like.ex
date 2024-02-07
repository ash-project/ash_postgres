defmodule AshPostgres.Functions.Like do
  @moduledoc """
  Maps to the builtin postgres function `like`.
  """

  use Ash.Query.Function, name: :like, predicate?: true

  def args, do: [[:string, :string]]
end
