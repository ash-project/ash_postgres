# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Subquery.ParentDomain do
  @moduledoc false
  alias AshPostgres.Test.Subquery.Access
  alias AshPostgres.Test.Subquery.Parent
  use Ash.Domain

  resources do
    resource(Parent)
    resource(Access)
  end

  authorization do
    authorize(:when_requested)
  end
end
