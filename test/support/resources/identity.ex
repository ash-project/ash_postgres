# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Identity do
  @moduledoc false
  use Ash.TypedStruct

  typed_struct do
    field(:provider, :string, allow_nil?: false)
    field(:uid, :string, allow_nil?: false)
  end
end
