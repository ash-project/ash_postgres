defmodule AshPostgres.TestCustomExtension do
  @moduledoc false

  use AshPostgres.CustomExtension, name: "demo-functions", latest_version: 1

  @impl true
  def install(0) do
    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_demo_functions()
    RETURNS boolean AS $$ SELECT TRUE $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")
    """
  end

  @impl true
  def install(1) do
    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_demo_functions()
    RETURNS boolean AS $$ SELECT FALSE $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")
    """
  end

  @impl true
  def uninstall(_version) do
    """
    execute(\"\"\"
    DROP FUNCTION IF EXISTS ash_demo_functions()
    \"\"\")
    """
  end
end
