defmodule AshPostgres.Test.User do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])

    update :accept_invite do
      require_atomic?(false)
      change(atomic_update(:role, expr(invite.role)))
    end

    read :active do
      filter(expr(active))

      pagination do
        offset?(true)
        keyset?(true)
        countable(true)
        required?(false)
      end
    end

    read :keyset do
      pagination do
        keyset?(true)
        countable(true)
        required?(false)
      end
    end
  end

  calculations do
    calculate(:active, :boolean, expr(is_active == true))
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:is_active, :boolean, public?: true)
    attribute(:name, :string, public?: true)
    attribute(:role, AshPostgres.Test.Role, allow_nil?: false, default: :user, public?: true)
  end

  postgres do
    table "users"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to :organization, AshPostgres.Test.Organization do
      public?(true)
      attribute_writable?(true)
    end

    has_many(:accounts, AshPostgres.Test.Account) do
      public?(true)
    end

    has_one(:invite, AshPostgres.Test.Invite) do
      source_attribute(:name)
      destination_attribute(:name)
    end
  end
end
