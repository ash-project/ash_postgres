# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Test.Support.Types.Email do
  @moduledoc false
  use Ash.Type.NewType,
    subtype_of: :ci_string,
    constraints: [
      casing: :lower
    ]
end
