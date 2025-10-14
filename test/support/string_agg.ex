# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.StringAgg do
  @moduledoc false
  use Ash.Resource.Aggregate.CustomAggregate
  use AshPostgres.CustomAggregate

  require Ecto.Query

  def dynamic(opts, binding) do
    Ecto.Query.dynamic(
      [],
      fragment("string_agg(?, ?)", field(as(^binding), ^opts[:field]), ^opts[:delimiter])
    )
  end
end
