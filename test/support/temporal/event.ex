# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Temporal.Event do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Temporal.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("event")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    attribute(:id, :integer, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)
    attribute(:created, :utc_datetime_usec, public?: true)
  end

  calculations do
    calculate(:now_val, :utc_datetime_usec, expr(now()))
    calculate(:is_past, :boolean, expr(created < now()))
    # `ago`/`from_now` anchored to `as_of` (field ref -> pushed to SQL).
    calculate(:within_a_year, :boolean, expr(created > ago(1, :year)))
    calculate(:within_next_year, :boolean, expr(created < from_now(1, :year)))
  end

  actions do
    defaults([:read])

    update :touch do
      require_atomic?(true)
      change(atomic_update(:created, expr(now())))
    end
  end
end
