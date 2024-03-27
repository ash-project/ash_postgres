defmodule AshPostgres.Test.CompositePoint do
  @moduledoc false
  use Ash.Type

  def storage_type(_), do: :custom_point

  def composite?(_constraints) do
    true
  end

  def composite_types(_constraints) do
    [{:x, :integer, []}, {:y, :integer, []}]
  end

  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(%{x: a, y: b}, _) when is_integer(a) and is_integer(b) do
    {:ok, %{x: a, y: b}}
  end

  def cast_input({a, b}, _) when is_integer(a) and is_integer(b) do
    {:ok, %{x: a, y: b}}
  end

  def cast_input(_, _), do: :error

  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(%{x: a, y: b}, _) when is_integer(a) and is_integer(b) do
    {:ok, %{x: a, y: b}}
  end

  def cast_stored({a, b}, _) when is_integer(a) and is_integer(b) do
    {:ok, %{x: a, y: b}}
  end

  def cast_stored(_, _) do
    :error
  end

  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%{x: a, y: b}, _) when is_integer(a) and is_integer(b) do
    {:ok, {a, b}}
  end

  def dump_to_native(_, _) do
    :error
  end
end
