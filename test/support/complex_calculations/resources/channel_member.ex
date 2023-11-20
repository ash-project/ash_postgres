defmodule AshPostgres.Test.ComplexCalculations.ChannelMember do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)

    create_timestamp(:created_at, private?: false)
    update_timestamp(:updated_at, private?: false)
  end

  postgres do
    table "complex_calculations_certifications_channel_members"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    belongs_to(:user, AshPostgres.Test.User, api: AshPostgres.Test.Api, attribute_writable?: true)

    belongs_to(:channel, AshPostgres.Test.ComplexCalculations.Channel, attribute_writable?: true)
  end
end
