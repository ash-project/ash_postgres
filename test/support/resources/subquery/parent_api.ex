defmodule AshPostgres.Test.Subquery.ParentApi do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Access
  alias AshPostgres.Test.Subquery.Parent
  use Ash.Api

  resources do
    resource(Parent)
    resource(Access)
  end
end
