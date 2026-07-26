# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddReadActionAggregateTables do
  @moduledoc """
  Tables for the aggregate `read_action` regression tests
  (test/aggregate_read_action_test.exs).

  The resources live inline in that test file (they are not part of
  AshPostgres.Test.Domain), so these tables are maintained by hand
  rather than by the migration generator.
  """
  use Ecto.Migration

  def up do
    create table(:read_action_ticket_folders, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)
    end

    create table(:read_action_ticket_lists, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)
      add(:name, :text)
      add(:ticket_folder_id, :uuid)
    end

    create table(:read_action_tickets, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)
      add(:title, :text)
      add(:status, :text, null: false, default: "open")
      add(:ticket_list_id, :uuid)
    end

    create table(:read_action_ticket_notes, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)
      add(:body, :text)
      add(:ticket_id, :uuid)
    end

    create table(:read_action_ticket_shares, primary_key: false) do
      add(:id, :uuid, null: false, primary_key: true)
      add(:ticket_folder_id, :uuid, null: false)
      add(:ticket_id, :uuid, null: false)
    end
  end

  def down do
    drop(table(:read_action_ticket_shares))
    drop(table(:read_action_ticket_notes))
    drop(table(:read_action_tickets))
    drop(table(:read_action_ticket_lists))
    drop(table(:read_action_ticket_folders))
  end
end
