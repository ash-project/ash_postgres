# SPDX-FileCopyrightText: 2020 Zach Daniel
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
