# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Test.LabelledContent do
  @moduledoc false
  use Ash.Resource,
    domain: AshPostgres.Test.Domain,
    data_layer: AshPostgres.DataLayer

  alias AshPostgres.Test.Label

  attributes do
    uuid_primary_key(:id)

    attribute(:content_id, :uuid, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:label, Label, allow_nil?: false)
  end

  postgres do
    repo AshPostgres.TestRepo

    polymorphic? true

    custom_indexes do
      index :content_id
      index :label_id
    end

    references do
      reference :label, on_delete: :delete
    end
  end

  actions do
    default_accept(:*)
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      argument(:label, :map)
      argument(:label_id, :integer)
    end
  end

  identities do
    identity(:unique_content_id_and_label_id, [
      :content_id,
      :label_id
    ])
  end

  changes do
    change(manage_relationship(:label, type: :append))
    change(manage_relationship(:label_id, :label, type: :append))
  end
end
