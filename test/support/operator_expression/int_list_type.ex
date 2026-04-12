# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.OperatorExpression.IntListType do
  @moduledoc """
  Custom type that overloads the `in` operator and rewrites it to a custom expression
  via operator_expression/1.
  """
  use Ash.Type

  @impl true
  def storage_type(_), do: {:array, :integer}

  @impl true
  def cast_input(%MapSet{} = set, constraints), do: cast_input(MapSet.to_list(set), constraints)

  def cast_input(list, _) when is_list(list) do
    if Enum.all?(list, &is_integer/1), do: {:ok, list}, else: :error
  end

  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(_, _), do: :error

  @impl true
  def cast_stored(value, constraints), do: cast_input(value, constraints)

  @impl true
  def dump_to_native(value, _) when is_list(value), do: {:ok, value}
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(_, _), do: :error

  @impl true
  def operator_overloads do
    %{
      in: %{
        [:integer, __MODULE__] => __MODULE__
      }
    }
  end

  @impl true
  def evaluate_operator(%Ash.Query.Operator.In{left: left, right: right})
      when is_list(right) do
    {:known, left in right}
  end

  def evaluate_operator(_), do: :unknown

  @impl true
  def operator_expression(%Ash.Query.Operator.In{}) do
    {:ok, AshPostgres.Test.OperatorExpression.IntListContains}
  end

  def operator_expression(_), do: :unknown
end
