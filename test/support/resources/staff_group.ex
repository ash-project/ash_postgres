# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.StaffGroup do
  @moduledoc false
  use Ash.Resource,
    otp_app: :ash_postgres,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "staff_group"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    uuid_primary_key(:id)

    timestamps()
  end

  relationships do
    many_to_many :members, AshPostgres.Test.User do
      through(AshPostgres.Test.StaffGroupMember)
    end
  end

  aggregates do
    count(:members_count, :members)
  end
end
