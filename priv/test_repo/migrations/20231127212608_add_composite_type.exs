# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddCompositeType do
  use Ecto.Migration

  def change do
    execute("""
    CREATE TYPE custom_point AS (
      x bigint,
      y bigint
    );
    """,
    """
    DROP TYPE custom_point;
    """)
  end
end
