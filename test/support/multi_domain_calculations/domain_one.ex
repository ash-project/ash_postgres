defmodule AshPostgres.Test.MultiDomainCalculations.DomainOne do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.MultiDomainCalculations.DomainOne.Item)
  end
end
