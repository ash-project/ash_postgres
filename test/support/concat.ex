# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Concat do
  @moduledoc false
  use Ash.Resource.Calculation
  require Ash.Query

  def init(opts) do
    if opts[:keys] && is_list(opts[:keys]) && Enum.all?(opts[:keys], &is_atom/1) do
      {:ok, opts}
    else
      {:error, "Expected a `keys` option for which keys to concat"}
    end
  end

  def expression(opts, %{arguments: %{separator: separator}}) do
    Enum.reduce(opts[:keys], nil, fn key, expr ->
      if expr do
        if separator do
          expr(^expr <> ^separator <> ^ref(key))
        else
          expr(^expr <> ^ref(key))
        end
      else
        expr(^ref(key))
      end
    end)
  end

  def calculate(records, opts, %{separator: separator}) do
    Enum.map(records, fn record ->
      Enum.map_join(opts[:keys], separator, fn key ->
        to_string(Map.get(record, key))
      end)
    end)
  end
end
