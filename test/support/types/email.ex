# SPDX-FileCopyrightText: 2020 Zach Daniel
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
