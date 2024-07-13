defmodule AshPostgres.Test.MultiDomainCalculations.DomainTwo do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem)
    resource(AshPostgres.Test.MultiDomainCalculations.DomainTwo.SubItem)
  end
end
