defmodule AshPostgres.Test.Author do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("authors")
    repo(AshPostgres.TestRepo)
  end

  attributes do
    uuid_primary_key(:id, writable?: true)
    attribute(:first_name, :string)
    attribute(:last_name, :string)
  end

  calculations do
    calculate(:full_name, :string, expr(first_name <> " " <> last_name))

    calculate(
      :conditional_full_name,
      :string,
      expr(
        if(
          is_nil(first_name) or is_nil(last_name),
          "(none)",
          first_name <> " " <> last_name
        )
      )
    )

    calculate(
      :nested_conditional,
      :string,
      expr(
        if(
          is_nil(first_name),
          "No First Name",
          if(
            is_nil(last_name),
            "No Last Name",
            first_name <> " " <> last_name
          )
        )
      )
    )

    calculate :param_full_name,
              :string,
              {AshPostgres.Test.Concat, keys: [:first_name, :last_name]} do
      argument(:separator, :string, default: " ", constraints: [allow_empty?: true, trim?: false])
    end
  end
end
