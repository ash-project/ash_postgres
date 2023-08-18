defmodule AshPostgres.Test.Point do
  @moduledoc false
  use Ash.Type

  def storage_type(_), do: {:array, :float}

  def cast_input(nil, _), do: {:ok, nil}

  def cast_input({a, b, c}, _) when is_float(a) and is_float(b) and is_float(c) do
    {:ok, {a, b, c}}
  end

  def cast_input(_, _), do: :error

  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored([a, b, c], _) when is_float(a) and is_float(b) and is_float(c) do
    {:ok, {a, b, c}}
  end

  def cast_stored(_, _) do
    :error
  end

  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native({a, b, c}, _) when is_float(a) and is_float(b) and is_float(c) do
    {:ok, [a, b, c]}
  end

  def dump_to_native(_, _) do
    :error
  end
end
