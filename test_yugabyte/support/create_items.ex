# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.Yugabyte.CreateItems do
  @moduledoc false
  use Ecto.Migration

  @disable_ddl_transaction true

  def change do
    create table(:items, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:key, :text, null: false)
      add(:value, :text)
      add(:score, :bigint, default: 0)
    end

    create(unique_index(:items, [:key], name: :items_unique_key_index))
  end
end
