defmodule AshPostgres.Test.Money do
  use Ash.Resource,
    data_layer: :embedded

  attributes do
    attribute :amount, :integer do
      allow_nil?(false)
      constraints(min: 0)
    end

    attribute :currency, :atom do
      constraints(one_of: [:eur, :usd])
    end
  end
end
