defmodule AshPostgres.MultitenancyTest.Api do
  @moduledoc false
  use Ash.Api

  resources do
    resource(AshPostgres.MultitenancyTest.Org)
    resource(AshPostgres.MultitenancyTest.Post)
  end
end
