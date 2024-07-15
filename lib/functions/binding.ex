defmodule AshPostgres.Functions.Binding do
  @moduledoc """
  Refers to the current table binding.
  """

  use Ash.Query.Function, name: :binding

  def args, do: [[]]
end
