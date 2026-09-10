# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Comment.TitleInList do
  @moduledoc """
  A calculation module (as opposed to an inline `expr`) whose expression
  references one of its own arguments.
  """
  use Ash.Resource.Calculation

  @impl true
  def expression(_opts, _context) do
    expr(title in ^arg(:titles))
  end
end
