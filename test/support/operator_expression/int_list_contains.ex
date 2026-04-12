# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.OperatorExpression.IntListContains do
  @moduledoc """
  Custom expression that replaces `value in list` with `value = ANY(array)` in postgres.

  This demonstrates operator_expression/1 rewriting an operator to a custom expression
  that compiles to a different (potentially more efficient) SQL form.
  """
  use Ash.CustomExpression,
    name: :int_list_contains,
    arguments: [
      [:integer, AshPostgres.Test.OperatorExpression.IntListType]
    ]

  def expression(AshPostgres.DataLayer, [value, list]) do
    {:ok, expr(fragment("custom_any(?, ?)", ^value, ^list))}
  end

  def expression(data_layer, [value, list])
      when data_layer in [Ash.DataLayer.Ets, Ash.DataLayer.Simple] do
    {:ok, expr(fragment(&__MODULE__.contains/2, ^value, ^list))}
  end

  def expression(_data_layer, _args), do: :unknown

  def contains(value, list) when is_list(list) do
    value in list
  end
end
