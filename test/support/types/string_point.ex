defmodule AshPostgres.Test.StringPoint do
  @moduledoc false
  use Ash.Type

  defstruct [:x, :y, :z]

  @type t :: %__MODULE__{
          x: float(),
          y: float(),
          z: float()
        }

  def storage_type(_), do: :string

  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(%__MODULE__{} = a, _) do
    {:ok, a}
  end

  def cast_input({x, y, z}, _) when is_float(x) and is_float(y) and is_float(z) do
    {:ok, %__MODULE__{x: x, y: y, z: z}}
  end

  def cast_input(enc, _) when is_binary(enc) do
    {:ok, parse!(enc)}
  end

  def cast_input(_, _), do: :error

  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(enc, _) when is_binary(enc) do
    {:ok, parse!(enc)}
  end

  def cast_stored(_, _) do
    :error
  end

  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%__MODULE__{x: x, y: y, z: z}, _) do
    enc = Enum.map_join([x, y, z], ",", &Float.to_string/1)

    {:ok, enc}
  end

  def dump_to_native(_, _) do
    :error
  end

  defp parse!(enc) when is_binary(enc) do
    [x, y, z] =
      String.split(enc, ",")
      |> Enum.map(&String.to_float/1)

    %__MODULE__{x: x, y: y, z: z}
  end
end
