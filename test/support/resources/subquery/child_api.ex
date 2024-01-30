defmodule AshPostgres.Test.Subquery.ChildApi do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Child
  alias AshPostgres.Test.Subquery.Through
  use Ash.Api

  resources do
    resource(Child)
    resource(Through)
  end
end
