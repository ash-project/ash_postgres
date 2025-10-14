# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Settings do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute(:dues_reminders, {:array, :string}, public?: true)
    attribute(:newsletter, {:array, :string}, public?: true)
    attribute(:optional_field, :string, public?: true)
  end
end
