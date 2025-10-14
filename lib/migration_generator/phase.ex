# SPDX-FileCopyrightText: 2019 ash_postgres contributors <https://github.com/ash-project/ash_postgres/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshPostgres.MigrationGenerator.Phase do
  @moduledoc false

  defmodule Create do
    @moduledoc false
    defstruct [:table, :schema, :multitenancy, :repo, operations: [], commented?: false]

    import AshPostgres.MigrationGenerator.Operation.Helper, only: [as_atom: 1]

    def up(%{
          schema: schema,
          table: table,
          operations: operations,
          multitenancy: multitenancy,
          repo: repo
        }) do
      if multitenancy.strategy == :context do
        "create table(:#{as_atom(table)}, primary_key: false, prefix: prefix()) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      else
        pre_create =
          if schema && repo.create_schemas_in_migrations?() do
            "execute(\"CREATE SCHEMA IF NOT EXISTS #{schema}\")" <> "\n\n"
          else
            ""
          end

        opts =
          if schema do
            ", prefix: \"#{schema}\""
          else
            ""
          end

        pre_create <>
          "create table(:#{as_atom(table)}, primary_key: false#{opts}) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      end
    end

    def down(%{schema: schema, table: table, multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "drop table(:#{as_atom(table)}, prefix: prefix())"
      else
        opts =
          if schema do
            ", prefix: \"#{schema}\""
          else
            ""
          end

        "drop table(:#{as_atom(table)}#{opts})"
      end
    end
  end

  defmodule Alter do
    @moduledoc false
    defstruct [:schema, :table, :multitenancy, operations: [], commented?: false]

    import AshPostgres.MigrationGenerator.Operation.Helper, only: [as_atom: 1]

    def up(%{table: table, schema: schema, operations: operations, multitenancy: multitenancy}) do
      body =
        operations
        |> Enum.map_join("\n", fn operation -> operation.__struct__.up(operation) end)
        |> String.trim()

      if body == "" do
        ""
      else
        if multitenancy.strategy == :context do
          "alter table(:#{as_atom(table)}, prefix: prefix()) do\n" <>
            body <>
            "\nend"
        else
          opts =
            if schema do
              ", prefix: \"#{schema}\""
            else
              ""
            end

          "alter table(:#{as_atom(table)}#{opts}) do\n" <>
            body <>
            "\nend"
        end
      end
    end

    def down(%{table: table, schema: schema, operations: operations, multitenancy: multitenancy}) do
      body =
        operations
        |> Enum.reverse()
        |> Enum.map_join("\n", fn operation -> operation.__struct__.down(operation) end)
        |> String.trim()

      if body == "" do
        ""
      else
        if multitenancy.strategy == :context do
          "alter table(:#{as_atom(table)}, prefix: prefix()) do\n" <>
            body <>
            "\nend"
        else
          opts =
            if schema do
              ", prefix: \"#{schema}\""
            else
              ""
            end

          "alter table(:#{as_atom(table)}#{opts}) do\n" <>
            body <>
            "\nend"
        end
      end
    end
  end
end
