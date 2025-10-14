# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Subquery.ChildDomain do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Child
  alias AshPostgres.Test.Subquery.Through
  use Ash.Domain

  resources do
    resource(Child)
    resource(Through)
  end

  authorization do
    authorize(:when_requested)
  end
end
