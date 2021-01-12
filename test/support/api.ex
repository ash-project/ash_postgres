defmodule AshPostgres.Test.Api do
  @moduledoc false
  use Ash.Api

  resources do
    resource AshPostgres.Test.Post
    resource AshPostgres.Test.Comment
  end
end
