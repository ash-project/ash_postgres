defmodule AshPostgres.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.CoAuthorPost)

    resource(AshPostgres.Test.Post) do
      define(:review, action: :review)
    end

    resource(AshPostgres.Test.Comedian)
    resource(AshPostgres.Test.Comment)
    resource(AshPostgres.Test.CommentLink)
    resource(AshPostgres.Test.IntegerPost)
    resource(AshPostgres.Test.Rating)
    resource(AshPostgres.Test.PostLink)
    resource(AshPostgres.Test.PostView)
    resource(AshPostgres.Test.Author)
    resource(AshPostgres.Test.Profile)
    resource(AshPostgres.Test.User)
    resource(AshPostgres.Test.Invite)
    resource(AshPostgres.Test.Joke)
    resource(AshPostgres.Test.Note)
    resource(AshPostgres.Test.StaffGroup)
    resource(AshPostgres.Test.StaffGroupMember)
    resource(AshPostgres.Test.Content)
    resource(AshPostgres.Test.Account)
    resource(AshPostgres.Test.Organization)
    resource(AshPostgres.Test.Manager)
    resource(AshPostgres.Test.Entity)
    resource(AshPostgres.Test.ContentVisibilityGroup)
    resource(AshPostgres.Test.TempEntity)
    resource(AshPostgres.Test.RecordTempEntity)
    resource(AshPostgres.Test.Permalink)
    resource(AshPostgres.Test.Record)
    resource(AshPostgres.Test.PostFollower)
    resource(AshPostgres.Test.StatefulPostFollower)
    resource(AshPostgres.Test.PostWithEmptyUpdate)
    resource(AshPostgres.Test.PartitionedPost)
    resource(AshPostgres.Test.DbPoint)
    resource(AshPostgres.Test.DbStringPoint)
    resource(AshPostgres.Test.CSV)
    resource(AshPostgres.Test.StandupClub)
    resource(AshPostgres.Test.Punchline)
    resource(AshPostgres.Test.Tag)
    resource(AshPostgres.Test.PostTag)
    resource(AshPostgres.Test.UnrelatedAggregatesTest.Profile)
    resource(AshPostgres.Test.UnrelatedAggregatesTest.SecureProfile)
    resource(AshPostgres.Test.UnrelatedAggregatesTest.Report)
    resource(AshPostgres.Test.UnrelatedAggregatesTest.User)
  end

  authorization do
    authorize(:when_requested)
  end
end
