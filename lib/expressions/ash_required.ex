# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Expressions.AshRequired do
  @moduledoc """
  Same as `Required` but with the explicit name `ash_required`.

  Use in filters as `ash_required(field)`. Equivalent to `required!(field)` and `not is_nil(field)`.

  Register in your config:

      config :ash, :custom_expressions, [
        AshPostgres.Expressions.Required,
        AshPostgres.Expressions.AshRequired
      ]
  """
  use Ash.CustomExpression,
    name: :ash_required,
    arguments: [[:any]],
    predicate?: true

  def expression(data_layer, args) do
    AshPostgres.Expressions.Required.expression(data_layer, args)
  end
end
