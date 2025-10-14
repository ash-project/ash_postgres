# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
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
