# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.BioAddress do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    attribute(:city, :string, public?: true)
    attribute(:country, :string, public?: true)
  end
end
