defmodule AshPostgres.MigrationGenerator.Phase do
  @moduledoc false

  defmodule Create do
    @moduledoc false
    defstruct [:table, :schema, :multitenancy, operations: [], commented?: false]

    def up(%{schema: schema, table: table, operations: operations, multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "create table(:#{table}, primary_key: false, prefix: prefix()) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      else
        opts =
          if schema do
            ", prefix: \"#{schema}\""
          else
            ""
          end

        "create table(:#{table}, primary_key: false#{opts}) do\n" <>
          Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end) <>
          "\nend"
      end
    end

    def down(%{schema: schema, table: table, multitenancy: multitenancy}) do
      if multitenancy.strategy == :context do
        "drop table(:#{inspect(table)}, prefix: prefix())"
      else
        opts =
          if schema do
            ", prefix: \"#{schema}\""
          else
            ""
          end

        "drop table(:#{inspect(table)}#{opts})"
      end
    end
  end

  defmodule Alter do
    @moduledoc false
    defstruct [:schema, :table, :multitenancy, operations: [], commented?: false]

    def up(%{table: table, schema: schema, operations: operations, multitenancy: multitenancy}) do
      body =
        Enum.map_join(operations, "\n", fn operation -> operation.__struct__.up(operation) end)

      if multitenancy.strategy == :context do
        "alter table(:#{table}, prefix: prefix()) do\n" <>
          body <>
          "\nend"
      else
        opts =
          if schema do
            ", prefix: \"#{schema}\""
          else
            ""
          end

        "alter table(:#{table}#{opts}) do\n" <>
          body <>
          "\nend"
      end
    end

    def down(%{table: table, schema: schema, operations: operations, multitenancy: multitenancy}) do
      body =
        operations
        |> Enum.reverse()
        |> Enum.map_join("\n", fn operation -> operation.__struct__.down(operation) end)

      if multitenancy.strategy == :context do
        "alter table(:#{table}, prefix: prefix()) do\n" <>
          body <>
          "\nend"
      else
        opts =
          if schema do
            ", prefix: \"#{schema}\""
          else
            ""
          end

        "alter table(:#{table}#{opts}) do\n" <>
          body <>
          "\nend"
      end
    end
  end
end
