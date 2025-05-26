defmodule AshPostgres.MultitenancyTest.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.MultitenancyTest.Org)
    resource(AshPostgres.MultitenancyTest.DevMigrationsOrg)
    resource(AshPostgres.MultitenancyTest.NamedOrg)
    resource(AshPostgres.MultitenancyTest.User)
    resource(AshPostgres.MultitenancyTest.Post)
    resource(AshPostgres.MultitenancyTest.PostLink)
    resource(AshPostgres.MultitenancyTest.NonMultitenantPostLink)
    resource(AshPostgres.MultitenancyTest.CrossTenantPostLink)
    resource(AshPostgres.MultitenancyTest.CompositeKeyPost)
  end

  authorization do
    authorize(:when_requested)
  end
end
