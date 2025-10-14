# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Tsvector do
  @moduledoc """
  A type for representing postgres' tsvectors.

  Values will be a list of `Postgrex.Lexeme`
  """

  use Ash.Type.NewType, subtype_of: :term

  @impl true
  def storage_type(_), do: :tsvector

  @impl true
  def cast_input(nil, _) do
    {:ok, nil}
  end

  def cast_input(values, _) when is_list(values) do
    if Enum.all?(values, &is_struct(&1, Postgrex.Lexeme)) do
      {:ok, values}
    else
      :error
    end
  end

  def cast_input(_, _) do
    :error
  end

  @impl true
  def dump_to_native(nil, _) do
    {:ok, nil}
  end

  def dump_to_native(values, _) when is_list(values) do
    if Enum.all?(values, &is_struct(&1, Postgrex.Lexeme)) do
      {:ok, values}
    else
      :error
    end
  end

  def dump_to_native(_, _) do
    :error
  end

  @impl true
  def cast_stored(nil, _) do
    {:ok, nil}
  end

  def cast_stored(values, _) when is_list(values) do
    if Enum.all?(values, &is_struct(&1, Postgrex.Lexeme)) do
      {:ok, values}
    else
      :error
    end
  end

  def cast_stored(_, _) do
    :error
  end
end
