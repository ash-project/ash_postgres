defmodule AshPostgres.Type.CiStringWrapper do
  @moduledoc false
  use Ash.Type.NewType, subtype_of: :ci_string, constraints: [allow_empty?: true, trim?: false]

  @impl true
  def storage_type(_), do: :citext
end
