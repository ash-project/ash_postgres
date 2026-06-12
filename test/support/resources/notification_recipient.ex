# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.NotificationRecipient do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "notification_recipients"
    repo AshPostgres.TestRepo

    identity_wheres_to_sql(post_user: "(post_id IS NOT NULL) AND (user_id IS NOT NULL)")
  end

  identities do
    identity(:post_user, [:post_id, :user_id],
      where: expr(not is_nil(post_id) and not is_nil(user_id))
    )
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:order, :integer, public?: true)
  end

  relationships do
    belongs_to :post, AshPostgres.Test.Post do
      public?(true)
      allow_nil?(true)
    end

    belongs_to :comment, AshPostgres.Test.Comment do
      public?(true)
      allow_nil?(true)
    end

    belongs_to :user, AshPostgres.Test.User do
      public?(true)
      allow_nil?(true)
    end

    belongs_to :staff_group, AshPostgres.Test.StaffGroup do
      public?(true)
      allow_nil?(true)
    end
  end
end
