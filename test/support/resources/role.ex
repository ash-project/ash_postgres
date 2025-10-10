# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Role do
  @moduledoc false

  use Ash.Type.Enum, values: [:admin, :user]
end
