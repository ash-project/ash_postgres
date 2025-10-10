# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.CreateTempSchema do
  use Ecto.Migration

  def up do
    execute("create schema if not exists \"temp\"")
  end

  def down do
    execute("drop schema if exists \"temp\"")
  end
end
