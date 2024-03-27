defmodule AshPostgres.MultitenancyTest.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.MultitenancyTest.Org)
    resource(AshPostgres.MultitenancyTest.User)
    resource(AshPostgres.MultitenancyTest.Post)
  end
end
