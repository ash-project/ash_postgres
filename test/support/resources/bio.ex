# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Bio do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded

  actions do
    default_accept(:*)

    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    attribute(:title, :string, public?: true)
    attribute(:bio, :string, public?: true)
    attribute(:years_of_experience, :integer, public?: true)

    attribute :list_of_strings, {:array, :string} do
      public?(true)
      allow_nil?(true)
      default(nil)
    end
  end
end
