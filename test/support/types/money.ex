# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Money do
  @moduledoc false
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :amount, :integer do
      public?(true)
      allow_nil?(false)
      constraints(min: 0)
    end

    attribute :currency, :atom do
      public?(true)
      constraints(one_of: [:eur, :usd])
    end
  end
end
