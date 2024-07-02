defmodule AshPostgres.MultitenancyTest.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.MultitenancyTest.Org)
    resource(AshPostgres.MultitenancyTest.User)
    resource(AshPostgres.MultitenancyTest.Post)
    resource(AshPostgres.MultitenancyTest.PostLink)
  end

  authorization do
    authorize(:when_requested)
  end
end
