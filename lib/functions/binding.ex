# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Functions.Binding do
  @moduledoc """
  Refers to the current table binding.
  """

  use Ash.Query.Function, name: :binding

  def args, do: [[]]
end
