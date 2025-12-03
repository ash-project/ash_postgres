# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Chat do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("chats")
    repo(AshPostgres.TestRepo)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :destroy, :update])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:name, :string, public?: true)
  end

  relationships do
    belongs_to :last_read_message, AshPostgres.Test.Message do
      allow_nil?(true)
      public?(true)
      attribute_writable?(true)
    end

    has_many :messages, AshPostgres.Test.Message do
      public?(true)
    end

    has_one :last_message, AshPostgres.Test.Message do
      public?(true)
      from_many?(true)
      sort(sent_at: :desc)
    end

    has_one :last_unread_message, AshPostgres.Test.Message do
      public?(true)
      from_many?(true)
      filter(expr(is_nil(read_at)))
      sort(sent_at: :desc)
    end

    has_many :unread_messages, AshPostgres.Test.Message do
      public?(true)
      no_attributes?(true)
      filter(expr(is_nil(parent(last_read_message_id)) or id > parent(last_read_message_id)))
    end
  end

  aggregates do
    count :unread_message_count, :messages do
      public?(true)
      filter(expr(is_nil(parent(last_read_message_id)) or id > parent(last_read_message_id)))
    end

    count :unread_messages_count_alt, :unread_messages do
      public?(true)
    end
  end
end
