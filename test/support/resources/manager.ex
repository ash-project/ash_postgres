defmodule AshPostgres.Test.Manager do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("managers")
    repo(AshPostgres.TestRepo)
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      primary?(true)
      argument(:organization_id, :uuid, allow_nil?: false)

      change(manage_relationship(:organization_id, :organization, type: :append_and_remove))
    end
  end

  identities do
    identity(:uniq_code, :code)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string)
    attribute(:code, :string, allow_nil?: false)
    attribute(:must_be_present, :string, allow_nil?: false)
    attribute(:role, :string)
  end

  relationships do
    belongs_to :organization, AshPostgres.Test.Organization do
      attribute_writable?(true)
    end
  end
end
