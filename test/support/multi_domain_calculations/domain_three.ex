defmodule AshPostgres.Test.MultiDomainCalculations.DomainThree do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.MultiDomainCalculations.DomainThree.RelationshipItem)
  end
end
