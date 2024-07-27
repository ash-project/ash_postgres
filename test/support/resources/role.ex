defmodule AshPostgres.Test.Role do
  @moduledoc false

  use Ash.Type.Enum, values: [:admin, :user]
end
