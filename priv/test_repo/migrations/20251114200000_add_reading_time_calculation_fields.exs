# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddReadingTimeCalculationFields do
  @moduledoc """
  Adds fields needed for testing estimated_reading_time calculation pattern.

  Manually created to test complex calculation with filtered aggregates.
  """

  use Ecto.Migration

  def up do
    alter table(:posts) do
      add(:base_reading_time, :integer)
    end

    alter table(:comments) do
      add(:edited_duration, :integer)
      add(:planned_duration, :integer)
      add(:reading_time, :integer)
      add(:version, :text)
      add(:status, :text)
    end
  end

  def down do
    alter table(:comments) do
      remove(:status)
      remove(:version)
      remove(:reading_time)
      remove(:planned_duration)
      remove(:edited_duration)
    end

    alter table(:posts) do
      remove(:base_reading_time)
    end
  end
end