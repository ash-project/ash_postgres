# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.MultiDomainCalculations.DomainThree do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.MultiDomainCalculations.DomainThree.RelationshipItem)
  end
end
