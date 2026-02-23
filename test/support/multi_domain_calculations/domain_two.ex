# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.MultiDomainCalculations.DomainTwo do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshPostgres.Test.MultiDomainCalculations.DomainTwo.OtherItem)
    resource(AshPostgres.Test.MultiDomainCalculations.DomainTwo.SubItem)
  end
end
