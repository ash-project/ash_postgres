defmodule AshPostgres.MultitenancyTest.NamedOrg do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.MultitenancyTest.Domain,
    data_layer: AshPostgres.DataLayer

  defimpl Ash.ToTenant do
    def to_tenant(%{name: name}, resource) do
      if Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer &&
           Ash.Resource.Info.multitenancy_strategy(resource) == :context do
        "org_#{name}"
      else
        name
      end
    end
  end

  attributes do
    attribute(:name, :string,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true
    )
  end

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  postgres do
    table "multitenant_named_orgs"
    repo(AshPostgres.TestRepo)

    manage_tenant do
      template(["org_", :name])
    end
  end
end
