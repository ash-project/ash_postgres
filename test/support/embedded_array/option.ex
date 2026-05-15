# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.EmbeddedArray.Option do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  alias AshPostgres.Test.EmbeddedArray.LineItem

  attributes do
    attribute :name, :string, public?: true
    attribute :total_amt, :decimal, public?: true
    attribute :quantity, :integer, public?: true
    attribute :active, :boolean, public?: true
    attribute :tier, :atom, public?: true, constraints: [one_of: [:basic, :premium, :enterprise]]
    attribute :valid_until, :utc_datetime, public?: true
    attribute :line_items, {:array, LineItem}, public?: true, default: []
  end
end
