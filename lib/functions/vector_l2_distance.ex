# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Functions.VectorL2Distance do
  @moduledoc """
  Maps to the vector l2 distance operator. Requires `vector` extension to be installed.
  """

  use Ash.Query.Function, name: :vector_l2_distance

  def args, do: [[:vector, :vector]]

  def returns, do: [:float]
end
