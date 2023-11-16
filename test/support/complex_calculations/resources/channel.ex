defmodule AshPostgres.Test.ComplexCalculations.Channel do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Expr

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)

    create_timestamp(:created_at, private?: false)
    update_timestamp(:updated_at, private?: false)
  end

  postgres do
    table "complex_calculations_channels"
    repo(AshPostgres.TestRepo)
  end

  relationships do
    has_many(:channel_members, AshPostgres.Test.ComplexCalculations.ChannelMember)

    has_one :first_member, AshPostgres.Test.ComplexCalculations.ChannelMember do
      destination_attribute(:channel_id)
      from_many?(true)
      sort(created_at: :asc)
    end

    has_one :second_member, AshPostgres.Test.ComplexCalculations.ChannelMember do
      destination_attribute(:channel_id)
      from_many?(true)
      sort(created_at: :desc)
    end
  end

  aggregates do
    first(:first_member_name, [:first_member, :user], :name)
    first(:second_member_name, [:second_member, :user], :name)
  end

  calculations do
    calculate :name, :string do
      calculation(
        expr(
          cond do
            first_member.user_id == ^actor(:id) ->
              first_member_name

            second_member.user_id == ^actor(:id) ->
              second_member_name

            true ->
              first_member_name <> ", " <> second_member_name
          end
        )
      )
    end
  end
end
