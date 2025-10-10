# SPDX-FileCopyrightText: 2020 Zach Daniel
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
