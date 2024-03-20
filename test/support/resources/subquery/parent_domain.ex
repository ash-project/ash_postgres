defmodule AshPostgres.Test.Subquery.ParentDomain do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Access
  alias AshPostgres.Test.Subquery.Parent
  use Ash.Domain

  resources do
    resource(Parent)
    resource(Access)
  end
end
