# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Preference do
  @moduledoc false
  use Ash.TypedStruct

  typed_struct do
    field(:key, :string, allow_nil?: false)
    field(:value, :string, allow_nil?: false)
  end
end
