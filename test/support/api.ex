defmodule AshPostgres.Test.Api do
  @moduledoc false
  use Ash.Api

  resources do
    resource(AshPostgres.Test.Post)
    resource(AshPostgres.Test.Comment)
    resource(AshPostgres.Test.IntegerPost)
    resource(AshPostgres.Test.Rating)
    resource(AshPostgres.Test.PostLink)
  end
end
