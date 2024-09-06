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
    resource(AshPostgres.Test.Permalink)
    resource(AshPostgres.Test.Record)
    resource(AshPostgres.Test.PostFollower)
    resource(AshPostgres.Test.StatefulPostFollower)
  end

  authorization do
    authorize(:when_requested)
  end
end
