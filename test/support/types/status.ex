# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Types.Status do
  @moduledoc false
  use Ash.Type.Enum, values: [:open, :closed]

  def storage_type, do: :string
end
