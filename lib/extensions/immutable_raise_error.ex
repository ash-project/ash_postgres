defmodule AshPostgres.Extensions.ImmutableRaiseError do
  @moduledoc """
  An extension that installs an immutable version of ash_raise_error.

  This can be used to improve compatibility with Postgres sharding extensions like Citus,
  which requires functions used in CASE or COALESCE expressions to be immutable.

  The new `ash_raise_error_immutable` functions add an additional row-dependent argument to ensure
  the planner doesn't constant-fold error expressions.

  To install, add this module to your repo's `installed_extensions` list:

  ```elixir
  def installed_extensions do
    ["ash-functions", AshPostgres.Extensions.ImmutableRaiseError]
  end
  ```

  And run `mix ash_postgres.generate_migrations` to generate the migrations.

  Once installed, you can control whether the immutable function is used by adding this to your
  repo:

  ```elixir
  def immutable_expr_error?, do: true
  ```
  """

  use AshPostgres.CustomExtension, name: "immutable_raise_error", latest_version: 1

  @impl true
  def install(0) do
    ash_raise_error_immutable()
  end

  @impl true
  def uninstall(_version) do
    "execute(\"DROP FUNCTION IF EXISTS ash_raise_error_immutable(jsonb, ANYCOMPATIBLE), ash_raise_error_immutable(jsonb, ANYELEMENT, ANYCOMPATIBLE)\")"
  end

  defp ash_raise_error_immutable do
    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_raise_error_immutable(json_data jsonb, token ANYCOMPATIBLE)
    RETURNS BOOLEAN AS $$
    BEGIN
        -- Raise an error with the provided JSON data.
        -- The JSON object is converted to text for inclusion in the error message.
        -- 'token' is intentionally ignored; its presence makes the call non-constant at the call site.
        RAISE EXCEPTION 'ash_error: %', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = '';
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_raise_error_immutable(json_data jsonb, type_signal ANYELEMENT, token ANYCOMPATIBLE)
    RETURNS ANYELEMENT AS $$
    BEGIN
        -- Raise an error with the provided JSON data.
        -- The JSON object is converted to text for inclusion in the error message.
        -- 'token' is intentionally ignored; its presence makes the call non-constant at the call site.
        RAISE EXCEPTION 'ash_error: %', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql
    IMMUTABLE
    SET search_path = '';
    \"\"\")
    """
  end
end
