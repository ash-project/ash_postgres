# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.EmbeddedArray.LineItem do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :name, :string, public?: true
    attribute :quantity, :integer, public?: true, default: 1
    attribute :unit_price, :decimal, public?: true
  end
end
