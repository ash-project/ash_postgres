defmodule AshPostgres.Functions.Type do
  @moduledoc """
  A function that maps to ecto's `type` function

  https://hexdocs.pm/ecto/Ecto.Query.API.html#type/2
  """

  use Ash.Query.Function, name: :type

  def args, do: [:any, :any]

  def new([left, right]) do
    right =
      if is_atom(right) || is_binary(right) do
        {:embed, right}
      else
        right
      end

    {:ok, %__MODULE__{arguments: [left, right]}}
  end
end
