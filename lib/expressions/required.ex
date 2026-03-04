# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Expressions.Required do
  @moduledoc """
  Custom expression that means "value must be present (not null)".

  Use in filters as `required!(field)` or `ash_required(field)`.
  Equivalent to `not is_nil(field)`; compiles to `(expr) IS NOT NULL` in SQL.

  Register in your config so Ash knows about it:

      config :ash, :custom_expressions, [
        AshPostgres.Expressions.Required,
        AshPostgres.Expressions.AshRequired
      ]
  """
  use Ash.CustomExpression,
    name: :required!,
    arguments: [[:any]],
    predicate?: true

  require Ash.Expr

  def expression(AshPostgres.DataLayer, [arg]) do
    {:ok, Ash.Expr.expr(not is_nil(^arg))}
  end

  def expression(_data_layer, _args), do: :unknown
end
