defmodule AshPostgres.Type.StringWrapper do
  @moduledoc false
  use Ash.Type

  @impl true
  def storage_type(_), do: :text

  @impl true
  defdelegate cast_input(value, constraints), to: Ash.Type.String
  @impl true
  defdelegate cast_stored(value, constraints), to: Ash.Type.String
  @impl true
  defdelegate dump_to_native(value, constraints), to: Ash.Type.String
end
