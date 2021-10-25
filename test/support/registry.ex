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
  end
end
