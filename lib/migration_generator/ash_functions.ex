defmodule AshPostgres.MigrationGenerator.AshFunctions do
  @latest_version 3

  def latest_version, do: @latest_version

  @moduledoc false
  def install(nil) do
    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_elixir_or(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE)
    AS $$ SELECT COALESCE(NULLIF($1, FALSE), $2) $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_elixir_or(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE)
    AS $$ SELECT COALESCE($1, $2) $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_elixir_and(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) AS $$
      SELECT CASE
        WHEN $1 IS TRUE THEN $2
        ELSE $1
      END $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_elixir_and(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) AS $$
      SELECT CASE
        WHEN $1 IS NOT NULL THEN $2
        ELSE $1
      END $$
    LANGUAGE SQL
    IMMUTABLE;
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_trim_whitespace(arr text[])
    RETURNS text[] AS $$
    DECLARE
        start_index INT = 1;
        end_index INT = array_length(arr, 1);
    BEGIN
        WHILE start_index <= end_index AND arr[start_index] = '' LOOP
            start_index := start_index + 1;
        END LOOP;

        WHILE end_index >= start_index AND arr[end_index] = '' LOOP
            end_index := end_index - 1;
        END LOOP;

        IF start_index > end_index THEN
            RETURN ARRAY[]::text[];
        ELSE
            RETURN arr[start_index : end_index];
        END IF;
    END; $$
    LANGUAGE plpgsql
    IMMUTABLE;
    \"\"\")

    #{ash_raise_error()}
    """
  end

  def install(0) do
    """
    execute(\"\"\"
    ALTER FUNCTION ash_elixir_or(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) IMMUTABLE
    \"\"\")

    execute(\"\"\"
    ALTER FUNCTION ash_elixir_or(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) IMMUTABLE
    \"\"\")

    execute(\"\"\"
    ALTER FUNCTION ash_elixir_and(left BOOLEAN, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) IMMUTABLE
    \"\"\")

    execute(\"\"\"
    ALTER FUNCTION ash_elixir_and(left ANYCOMPATIBLE, in right ANYCOMPATIBLE, out f1 ANYCOMPATIBLE) IMMUTABLE
    \"\"\")

    #{ash_raise_error()}

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_trim_whitespace(arr text[])
    RETURNS text[] AS $$
    DECLARE
        start_index INT = 1;
        end_index INT = array_length(arr, 1);
    BEGIN
        WHILE start_index <= end_index AND arr[start_index] = '' LOOP
            start_index := start_index + 1;
        END LOOP;

        WHILE end_index >= start_index AND arr[end_index] = '' LOOP
            end_index := end_index - 1;
        END LOOP;

        IF start_index > end_index THEN
            RETURN ARRAY[]::text[];
        ELSE
            RETURN arr[start_index : end_index];
        END IF;
    END; $$
    LANGUAGE plpgsql
    IMMUTABLE;
    \"\"\")
    """
  end

  def install(1) do
    ash_raise_error()
  end

  def install(2) do
    ash_raise_error()
  end

  def drop(2) do
    ash_raise_error(false)
  end

  def drop(1) do
    "execute(\"DROP FUNCTION IF EXISTS ash_raise_error(jsonb), ash_raise_error(jsonb, ANYCOMPATIBLE)\")"
  end

  def drop(0) do
    "execute(\"DROP FUNCTION IF EXISTS ash_raise_error(jsonb), ash_raise_error(jsonb, ANYCOMPATIBLE), ash_trim_whitespace(text[])\")"
  end

  def drop(nil) do
    "execute(\"DROP FUNCTION IF EXISTS ash_raise_error(jsonb), ash_raise_error(jsonb, ANYCOMPATIBLE), ash_elixir_and(BOOLEAN, ANYCOMPATIBLE), ash_elixir_and(ANYCOMPATIBLE, ANYCOMPATIBLE), ash_elixir_or(ANYCOMPATIBLE, ANYCOMPATIBLE), ash_elixir_or(BOOLEAN, ANYCOMPATIBLE), ash_trim_whitespace(text[])\")"
  end

  defp ash_raise_error(prefix? \\ true) do
    prefix =
      if prefix? do
        "ash_error: "
      else
        ""
      end

    """
    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_raise_error(json_data jsonb)
    RETURNS BOOLEAN AS $$
    BEGIN
        -- Raise an error with the provided JSON data.
        -- The JSON object is converted to text for inclusion in the error message.
        RAISE EXCEPTION '#{prefix}%', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    \"\"\")

    execute(\"\"\"
    CREATE OR REPLACE FUNCTION ash_raise_error(json_data jsonb, type_signal ANYCOMPATIBLE)
    RETURNS ANYCOMPATIBLE AS $$
    BEGIN
        -- Raise an error with the provided JSON data.
        -- The JSON object is converted to text for inclusion in the error message.
        RAISE EXCEPTION '#{prefix}%', json_data::text;
        RETURN NULL;
    END;
    $$ LANGUAGE plpgsql;
    \"\"\")
    """
  end
end
