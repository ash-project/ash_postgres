# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Functions.Binding do
  @moduledoc """
  Refers to the current table binding.
  """

  use Ash.Query.Function, name: :binding

  def args, do: [[]]
end
