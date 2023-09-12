defmodule AshPostgres.Functions.VectorCosineDistance do
  @moduledoc """
  Maps to the vector cosine distance operator. Requires `vector` extension to be installed.
  """

  use Ash.Query.Function, name: :vector_cosine_distance

  def args, do: [[:vector, :vector]]
end
