# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshPostgres.Test.Temporal.Subscription)
    resource(AshPostgres.Test.Temporal.Tier)
    resource(AshPostgres.Test.Temporal.Event)
  end
end
