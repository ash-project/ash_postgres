# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Types.StatusEnumNoCast do
  @moduledoc false
  use Ash.Type.Enum, values: [:open, :closed]

  @impl true
  def storage_type, do: :status

  @impl true
  def cast_in_query?(_), do: false
end
