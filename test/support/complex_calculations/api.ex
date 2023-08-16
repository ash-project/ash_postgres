defmodule AshPostgres.Test.ComplexCalculations.Api do
  @moduledoc false
  use Ash.Api

  resources do
    registry(AshPostgres.Test.ComplexCalculations.Registry)
  end
end
