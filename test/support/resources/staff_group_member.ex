# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.StaffGroupMember do
  @moduledoc false
  use Ash.Resource,
    otp_app: :ash_postgres,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "staff_group_member"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  attributes do
    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to(:staff_group, AshPostgres.Test.StaffGroup, primary_key?: true, allow_nil?: false)
    belongs_to(:user, AshPostgres.Test.User, primary_key?: true, allow_nil?: false)
  end
end
