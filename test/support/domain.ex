defmodule AshPostgres.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.Post)
    resource(AshPostgres.Test.Comment)
    resource(AshPostgres.Test.IntegerPost)
    resource(AshPostgres.Test.Rating)
    resource(AshPostgres.Test.PostLink)
    resource(AshPostgres.Test.PostView)
    resource(AshPostgres.Test.Author)
    resource(AshPostgres.Test.Profile)
    resource(AshPostgres.Test.User)
    resource(AshPostgres.Test.Invite)
    resource(AshPostgres.Test.Account)
    resource(AshPostgres.Test.Organization)
    resource(AshPostgres.Test.Manager)
    resource(AshPostgres.Test.Entity)
    resource(AshPostgres.Test.TempEntity)
    resource(AshPostgres.Test.Record)
    resource(AshPostgres.Test.PostFollower)
    resource(AshPostgres.Test.StatefulPostFollower)
    resource(CalcDependency.Dependency)
    resource(CalcDependency.Element)
    resource(CalcDependency.ElementContext)
    resource(CalcDependency.Location)
    resource(CalcDependency.Operation)
    resource(CalcDependency.OperationVersion)
    resource(CalcDependency.SchematicGroup)
    resource(CalcDependency.Segment)
    resource(CalcDependency.Verb)
  end

  authorization do
    authorize(:when_requested)
  end
end
