# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.ContentVisibilityGroup do
  @moduledoc false
  use Ash.Resource,
    otp_app: :ash_postgres,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "content_visibility_group"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end

  relationships do
    belongs_to(:content, AshPostgres.Test.Content, primary_key?: true, allow_nil?: false)
    belongs_to(:staff_group, AshPostgres.Test.StaffGroup, primary_key?: true, allow_nil?: false)
  end
end
