# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.TestRepo.Migrations.AddCustomAnyFunction do
  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION custom_any(value bigint, arr bigint[])
    RETURNS boolean AS $$
      SELECT value = ANY(arr);
    $$ LANGUAGE SQL IMMUTABLE;
    """
  end

  def down do
    execute "DROP FUNCTION IF EXISTS custom_any(bigint, bigint[]);"
  end
end
