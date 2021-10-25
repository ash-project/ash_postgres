defmodule AshPostgres.MultitenancyTest.Api do
  @moduledoc false
  use Ash.Api

  resources do
    registry(AshPostgres.MultitenancyTest.Registry)
  end
end
