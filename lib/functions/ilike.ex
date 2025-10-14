# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Functions.ILike do
  @moduledoc """
  Maps to the builtin postgres function `ilike`.
  """

  use Ash.Query.Function, name: :ilike, predicate?: true

  def args, do: [[:string, :string]]
end
