defmodule Ash.Type.CiStringWrapper do
  @moduledoc false
  use Ash.Type

  @impl true
  def storage_type, do: :citext

  @impl true
  defdelegate cast_input(value, constraints), to: Ash.Type.CiString
  @impl true
  defdelegate cast_stored(value, constraints), to: Ash.Type.CiString
  @impl true
  defdelegate dump_to_native(value, constraints), to: Ash.Type.CiString
end
