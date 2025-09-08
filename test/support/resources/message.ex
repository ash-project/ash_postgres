defmodule AshPostgres.Test.Message do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("messages")
    repo(AshPostgres.TestRepo)
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :destroy, :update])
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:content, :string, public?: true)
    attribute(:sent_at, :utc_datetime, default: &DateTime.utc_now/0, public?: true)
    attribute(:read_at, :utc_datetime, public?: true)
  end

  relationships do
    belongs_to :chat, AshPostgres.Test.Chat do
      public?(true)
      allow_nil?(false)
    end
  end
end