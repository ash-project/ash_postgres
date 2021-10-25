defmodule AshPostgres.Test.Api do
  @moduledoc false
  use Ash.Api

  resources do
    registry(AshPostgres.Test.Registry)
  end
end
