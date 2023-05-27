defmodule AshPostgres.Test.Registry do
  @moduledoc false
  use Ash.Registry

  entries do
    entry(AshPostgres.Test.Post)
    entry(AshPostgres.Test.Comment)
    entry(AshPostgres.Test.IntegerPost)
    entry(AshPostgres.Test.Rating)
    entry(AshPostgres.Test.PostLink)
    entry(AshPostgres.Test.Author)
    entry(AshPostgres.Test.Profile)
    entry(AshPostgres.Test.User)
    entry(AshPostgres.Test.Account)
    entry(AshPostgres.Test.Organization)
    entry(AshPostgres.Test.Manager)
  end
end
