defmodule AshPostgres.Test.ComplexCalculations.ChannelMember do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.ComplexCalculations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)

    create_timestamp(:created_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  postgres do
    table "complex_calculations_certifications_channel_members"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to(:user, AshPostgres.Test.User, domain: AshPostgres.Test.Domain, public?: true)

    belongs_to(:channel, AshPostgres.Test.ComplexCalculations.Channel, public?: true)
  end
end
