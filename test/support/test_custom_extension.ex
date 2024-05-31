defmodule AshPostgres.TestCustomExtension do
  @moduledoc false

  use AshPostgres.CustomExtension, name: "demo-functions", latest_version: 2

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
  def install(2) do
    """
    execute(\"\"\"
    DROP FUNCTION IF EXISTS ash_demo_functions();
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_demo_functions()
    RETURNS text AS $$ SELECT 'ok' $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")
    """
  end

  @impl true
  def uninstall(2) do
    """
    execute(\"\"\"
    DROP FUNCTION IF EXISTS ash_demo_functions();
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_demo_functions()
    RETURNS boolean AS $$ SELECT FALSE $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")
    """
  end

  def uninstall(_version) do
    """
    execute(\"\"\"
    DROP FUNCTION IF EXISTS ash_demo_functions()
    \"\"\")
    """
  end
end
