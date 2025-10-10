# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Type.StringWrapper do
  @moduledoc false
  use Ash.Type.NewType, subtype_of: :string, constraints: [allow_empty?: true, trim?: false]

  @impl true
  def storage_type(_), do: :text
end
