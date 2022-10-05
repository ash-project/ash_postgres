defmodule AshPostgres.Functions.Type do
  @moduledoc """
  A function that maps to ecto's `type` function

  https://hexdocs.pm/ecto/Ecto.Query.API.html#type/2
  """

  use Ash.Query.Function, name: :type

  def args, do: [[:any, :any], [:any, :any, :any]]

  def new([left, :citext]) do
    {:ok, %AshPostgres.Functions.Fragment{arguments: ["?::citext", left]}}
  end

  def new([left, :citext, constraints]) do
    {:ok,
     %__MODULE__{
       arguments: [
         %AshPostgres.Functions.Fragment{arguments: ["?::citext", left]},
         Ash.Type.CiString,
         constraints
       ]
     }}
  end

  def new([left, :binary_id]) when is_binary(left) do
    {:ok, %__MODULE__{arguments: [Ecto.UUID.dump!(left), {:embed, :binary_id}]}}
  end

  def new([left, Ash.Type.UUID]) when is_binary(left) do
    {:ok, %__MODULE__{arguments: [Ecto.UUID.dump!(left), {:embed, Ash.Type.UUID}]}}
  end

  def new([left, right]) do
    right =
      if is_atom(right) || match?({:array, type} when is_atom(type), right) do
        {:embed, right}
      else
        right
      end

    {:ok, %__MODULE__{arguments: [left, right]}}
  end

  def new([left, right, constraints]) do
    right =
      if is_atom(right) || match?({:array, type} when is_atom(type), right) do
        {:embed, right}
      else
        right
      end

    {:ok, %__MODULE__{arguments: [left, right, constraints]}}
  end
end
