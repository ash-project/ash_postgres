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
    attribute(:bio, AshPostgres.Test.Bio)
    attribute(:badges, {:array, :atom})
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  relationships do
    has_one(:profile, AshPostgres.Test.Profile)
    has_many(:posts, AshPostgres.Test.Post)
  end

  aggregates do
    first(:profile_description, :profile, :description)
  end

  calculations do
    calculate(
      :description,
      :string,
      expr(
        if is_nil(^actor(:id)) do
          "no actor"
        else
          profile_description
        end
      )
    )

    calculate(:title, :string, expr(bio[:title]))
    calculate(:full_name, :string, expr(first_name <> " " <> last_name))
    calculate(:full_name_with_nils, :string, expr(string_join([first_name, last_name], " ")))
    calculate(:full_name_with_nils_no_joiner, :string, expr(string_join([first_name, last_name])))
    calculate(:split_full_name, {:array, :string}, expr(string_split(full_name)))

    calculate(
      :split_full_name_trim,
      {:array, :string},
      expr(string_split(full_name, " ", trim?: true))
    )

    calculate(:first_name_from_split, :string, expr(at(split_full_name_trim, 0)))

    calculate(:first_name_or_bob, :string, expr(first_name || "bob"))
    calculate(:first_name_and_bob, :string, expr(first_name && "bob"))

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
