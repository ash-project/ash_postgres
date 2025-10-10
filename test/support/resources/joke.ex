# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.Joke do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key(:id)
    attribute(:text, :string, public?: true)
    attribute(:is_good, :boolean, default: false, public?: true)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  relationships do
    belongs_to(:standup_club, AshPostgres.Test.StandupClub, public?: true)
    belongs_to(:comedian, AshPostgres.Test.Comedian, public?: true)
    has_many(:punchlines, AshPostgres.Test.Punchline, public?: true)
  end

  actions do
    defaults([:read])
  end

  aggregates do
    count(:punchline_count, :punchlines, public?: true)
  end

  postgres do
    table("jokes")
    repo(AshPostgres.TestRepo)
  end
end
