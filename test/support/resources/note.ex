# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Note do
  @moduledoc false
  use Ash.Resource,
    otp_app: :ash_postgres,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "note"
    repo AshPostgres.TestRepo
  end

  actions do
    defaults([:read])

    read :failing_many_reference do
      pagination(keyset?: true, default_limit: 25)
      filter(expr(count_nils(content.visibility_group_staff_ids) == 0))
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :body, :string do
      allow_nil?(false)
      public?(true)
    end

    timestamps()
  end

  relationships do
    has_one(:content, AshPostgres.Test.Content)
  end
end
